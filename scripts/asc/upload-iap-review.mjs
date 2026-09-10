// Fill only the three verified purchase review-image slots. Default: read-only plan.
// Apple: /documentation/appstoreconnectapi/subscription-app-store-review-screenshots
// and /documentation/appstoreconnectapi/in-app-purchase-app-store-review-screenshots
import crypto from 'node:crypto'
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { AppStoreConnect } from './lib/asc.mjs'
import { inspectPng } from './lib/metadata.mjs'

const apply = process.argv.includes('--apply')
const folder = new URL('../../docs/validation/release-2026-09-10/iap-review/', import.meta.url)
const manifest = JSON.parse(readFileSync(new URL('manifest.json', folder), 'utf8'))
const products = [
  { name: 'weekly', id: '6810782782', productType: 'subscriptions', version: 'v1', type: 'subscriptionAppStoreReviewScreenshots', relationship: 'subscription' },
  { name: 'yearly', id: '6810785364', productType: 'subscriptions', version: 'v1', type: 'subscriptionAppStoreReviewScreenshots', relationship: 'subscription' },
  { name: 'lifetime', id: '6810786506', productType: 'inAppPurchases', version: 'v2', type: 'inAppPurchaseAppStoreReviewScreenshots', relationship: 'inAppPurchaseV2' },
].map(product => {
  const fileName = `${product.name}.png`
  const file = fileURLToPath(new URL(fileName, folder))
  const bytes = readFileSync(file)
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex')
  if (manifest.find(item => item.file === fileName)?.sha256 !== sha256) throw new Error(`${fileName}: source hash differs from the inspected capture manifest`)
  const png = inspectPng(file)
  if (!png || png.hasAlpha || png.width !== 1206 || png.height !== 2622) throw new Error(`${fileName}: unexpected review image format`)
  return { ...product, fileName, bytes, sha256, checksum: crypto.createHash('md5').update(bytes).digest('hex'), path: `/${product.version}/${product.productType}/${product.id}` }
})
if (process.argv.includes('--check')) {
  console.log('All three review images match their inspected hashes and RGB dimensions.')
  process.exit(0)
}

const client = AppStoreConnect.fromEnv()
const records = []
const report = { checkedAt: new Date().toISOString(), mode: apply ? 'apply' : 'plan', products: records }
function saveReport() {
  mkdirSync('apple-audit', { recursive: true })
  writeFileSync('apple-audit/iap-review.json', JSON.stringify(report, null, 2) + '\n')
}
function describe(asset) {
  if (!asset) return null
  const a = asset.attributes ?? {}
  return { id: asset.id, fileName: a.fileName, fileSize: a.fileSize, sourceFileChecksum: a.sourceFileChecksum, delivery: a.assetDeliveryState, image: a.imageAsset ? { width: a.imageAsset.width, height: a.imageAsset.height } : null }
}
// Read and validate every destination before the first reservation.
for (const product of products) {
  const data = (await client.get(product.path)).data
  if (data.attributes.productId !== `com.airlineempire.game.pro.${product.name}`) throw new Error(`${product.name}: product identity mismatch`)
  let existing
  try { existing = (await client.get(`${product.path}/appStoreReviewScreenshot`)).data }
  catch (error) { if (error.status !== 404) throw error }
  if (existing && (existing.attributes?.sourceFileChecksum !== product.checksum || existing.attributes?.assetDeliveryState?.state !== 'COMPLETE')) {
    throw new Error(`${product.name}: an existing review asset differs or is incomplete; leaving it untouched`)
  }
  records.push({ name: product.name, productId: data.attributes.productId, appleId: product.id, productState: data.attributes.state, sha256: product.sha256, action: existing ? 'already complete' : 'fill missing review image', asset: describe(existing) })
}
saveReport()
console.log(JSON.stringify(report, null, 2))
if (!apply) process.exit(0)

for (const [index, product] of products.entries()) {
  if (records[index].asset) continue
  const asset = (await client.request('POST', `/v1/${product.type}`, { attempts: 1, body: { data: {
    type: product.type,
    attributes: { fileName: product.fileName, fileSize: product.bytes.length },
    relationships: { [product.relationship]: { data: { type: product.productType, id: product.id } } },
  } } })).data
  records[index].asset = describe(asset)
  saveReport()
  const operations = asset.attributes?.uploadOperations ?? []
  if (!operations.length) throw new Error(`${product.name}: no upload operations returned`)
  for (const operation of operations) {
    if (new URL(operation.url).protocol !== 'https:' || !Number.isInteger(operation.offset) || !Number.isInteger(operation.length) || operation.offset < 0 || operation.length <= 0 || operation.offset + operation.length > product.bytes.length) throw new Error(`${product.name}: invalid upload operation`)
    // Use Apple's signed operation headers only; never send the ASC bearer token.
    let response
    try {
      response = await fetch(operation.url, {
        method: operation.method ?? 'PUT',
        headers: Object.fromEntries((operation.requestHeaders ?? []).map(h => [h.name, h.value])),
        body: product.bytes.subarray(operation.offset, operation.offset + operation.length),
        signal: AbortSignal.timeout(60000),
      })
    } catch { throw new Error(`${product.name}: upload transport failed; reservation retained for inspection`) }
    if (!response.ok) throw new Error(`${product.name}: chunk upload HTTP ${response.status}`)
  }
  await client.patch(`/v1/${product.type}/${asset.id}`, { data: { type: product.type, id: asset.id, attributes: { uploaded: true, sourceFileChecksum: product.checksum } } })
  let complete = false
  for (let attempt = 0; attempt < 40; attempt++) {
    const current = (await client.get(`/v1/${product.type}/${asset.id}`)).data
    records[index].asset = describe(current)
    saveReport()
    const state = current.attributes?.assetDeliveryState?.state
    if (state === 'FAILED') throw new Error(`${product.name}: Apple rejected the review image`)
    if (state === 'COMPLETE') {
      if (current.attributes.sourceFileChecksum !== product.checksum) throw new Error(`${product.name}: processed checksum mismatch`)
      const attached = (await client.get(`${product.path}/appStoreReviewScreenshot`)).data
      if (attached?.id !== asset.id) throw new Error(`${product.name}: processed asset is not attached to its product`)
      complete = true
      break
    }
    await new Promise(resolve => setTimeout(resolve, 3000))
  }
  if (!complete) throw new Error(`${product.name}: Apple image processing did not finish within the bounded wait`)
  records[index].productState = (await client.get(product.path)).data.attributes.state
  records[index].action = 'uploaded and verified'
  saveReport()
  console.log(`${product.name}: review image COMPLETE; checksum and product attachment verified.`)
}
