// Read-only snapshot of the owner's selected release territories.
import { mkdirSync, writeFileSync } from 'node:fs'
import { AppStoreConnect } from './lib/asc.mjs'

const client = AppStoreConnect.fromEnv()
const appId = '6806410538'
const app = (await client.get(`/v1/apps/${appId}/appAvailabilityV2`)).data
const territoryURL = new URL(app.relationships.territoryAvailabilities.links.related)
territoryURL.searchParams.set('include', 'territory')
const appTerritories = await client.getAll(territoryURL.href)
const products = await Promise.all([
  ['weekly', '/v1/subscriptions/6810782782/subscriptionAvailability'],
  ['yearly', '/v1/subscriptions/6810785364/subscriptionAvailability'],
  ['lifetime', '/v2/inAppPurchases/6810786506/inAppPurchaseAvailability'],
].map(async ([name, path]) => {
  const availability = (await client.get(path)).data
  const territories = await client.getAll(availability.relationships.availableTerritories.links.related)
  return { name, ...availability.attributes, territories: territories.map(t => t.id).sort() }
}))
const report = {
  checkedAt: new Date().toISOString(), appId,
  app: { ...app.attributes, territories: appTerritories.map(t => ({
    territory: t.relationships?.territory?.data?.id,
    ...t.attributes,
  })) },
  products,
}
mkdirSync('apple-audit', { recursive: true })
writeFileSync('apple-audit/territories.json', JSON.stringify(report, null, 2) + '\n')
console.log(`Read ${appTerritories.length} app territory rows and ${products.length} purchase availability records.`)
for (const p of products) console.log(`${p.name}: ${p.territories.length} territories; CHN=${p.territories.includes('CHN')}, VNM=${p.territories.includes('VNM')}`)
