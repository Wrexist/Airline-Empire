import fs from "node:fs";
export default async ({ project }) => {
  const config = JSON.parse(fs.readFileSync("clip-config.json", "utf8"));
  const p = await project({dir: config.name, size:"1080x1920", fps:30, background:"#07111d"});
  let at = 0;
  for (const shot of config.shots) {
    const source = await p.add(shot.source);
    p.compose(
      <frame layout="none" width={1080} height={1920}>
        <rect x={48} y={270} width={984} height={1360} radius={38} fill="#10243a"/>
        <frame x={78} y={280} width={924} height={1340} layout="column" align="center" justify="center">
          <media file={source} trimStart={shot.from} fit="contain" width={924} height={1340}/>
        </frame>
        <text x={72} y={60} width={936} height={42} fontFamily="Montserrat" fontWeight={600} fontSize={26} color="#62b7ff" align="center">AIRLINE EMPIRE · FLIGHT TYCOON</text>
        <text x={72} y={126} width={936} height={128} fontFamily="Montserrat" fontWeight={700} fontSize={52} lineHeight={1.15} color="#ffffff" align="center">{shot.title}</text>
        <text x={72} y={1660} width={936} height={56} fontFamily="Montserrat" fontWeight={600} fontSize={35} color="#ffffff" align="center">Follow the launch</text>
        <text x={72} y={1734} width={936} height={46} fontFamily="Montserrat" fontWeight={500} fontSize={29} color="#bed2e6" align="center">Planned 16 October · iPhone + iPad</text>
        <text x={72} y={1810} width={936} height={44} fontFamily="Montserrat" fontSize={24} color="#91abc2" align="center">Actual gameplay · Includes Pro content</text>
      </frame>,
      {at, dur:shot.duration, name:shot.label}
    );
    at += shot.duration;
  }
  await p.frame(2, "renders/preview.png");
  await p.render("renders/final.mp4", {depth:8,bitrate:8000000,concurrency:3});
};
