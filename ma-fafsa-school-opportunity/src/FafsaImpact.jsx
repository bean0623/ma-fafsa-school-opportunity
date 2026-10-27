import React from 'react';
import { ResponsiveContainer, ScatterChart, Scatter, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';
import { ArrowRight, ArrowUpRight, DownloadSimple } from '@phosphor-icons/react';
import { number, signed, TableDisclosure } from './charts';
import './evidence.css';

export const SOURCES = {
  assistance: 'https://oreopoulos.faculty.economics.utoronto.ca/wp-content/uploads/2020/05/bettinger-et-al-the-role-of-application-assistance-and-information-in-college-decisions-qje-2012.pdf',
  middleSchool: 'https://www.mefa.org/webinar/college-planning-for-middle-school-families/',
  attendance: 'https://ies.ed.gov/use-work/resource-library/report/impact-study/getting-students-track-graduation-impacts-early-warning-intervention-and-monitoring-system-after-one',
  fafsa: 'https://fsapartners.ed.gov/knowledge-center/fsa-handbook/2025-2026/application-and-verification-guide/ch1-application-process-fafsa-isir'
};
const groups = [
  {id:1, label:'Higher proportion', range:'59.8–95.8%', color:'#b77756'},
  {id:2, label:'Middle proportion', range:'28.9–59.5%', color:'#7b9694'},
  {id:3, label:'Lower proportion', range:'5.1–28.6%', color:'#183d50'}
];
export function EvidenceSource({href,children}) { return <a className="evidence-source" href={href} target="_blank" rel="noreferrer">{children}<ArrowUpRight size={15} aria-hidden="true"/></a>; }

function SchoolTooltip({active,payload}) {
  if (!active || !payload?.length) return null;
  const row = payload[0].payload;
  return <div className="impact-tooltip"><strong>{row.schoolName}</strong><span>FAFSA ratio: {number(row.fafsaPct)}%</span><span>College attendance: {number(row.collegeAttendancePct)}%</span><small>{groups.find(g=>g.id===row.ses3)?.label} · {number(row.lowIncomePct)}% low-income students</small></div>;
}

export function FafsaImpact({data}) {
  const evidence = data.fafsaCollege;
  if (!evidence) return null;
  const rows = evidence.scatter.rows;
  const model = evidence.existingStataAdjustedAssociation;
  const estimate = model.slope_per_10pp;
  return <section className="section fafsa-impact" aria-labelledby="fafsa-impact-title">
    <div className="section-head"><div><p className="eyebrow">Why FAFSA matters</p><h2 id="fafsa-impact-title">FAFSA completion and college attendance</h2></div></div>
    <p className="section-intro">FAFSA is required to be considered for federal student aid, but filing does not guarantee an award. The school data show a strong association between completion and college attendance.</p><p><EvidenceSource href={SOURCES.fafsa}>Federal Student Aid · Why the application is required</EvidenceSource></p>
    <div className="impact-grid">
      <div className="chart-panel">
        <figure className="impact-scatter" aria-labelledby="impact-scatter-title">
          <figcaption className="research-chart-heading"><h3 className="research-chart-title" id="impact-scatter-title">FAFSA ratios and college attendance in Massachusetts</h3><p className="research-chart-subtitle">Each dot is one school · {rows.length} schools with both measures · Class of 2025</p></figcaption>
          <p className="research-category-title">Students classified as low income (%)</p><div className="impact-legend" aria-label="Low-income proportion legend">{groups.map(group=><span key={group.id}><i style={{background:group.color}} aria-hidden="true"/><span>{group.label}<small>{group.range} of students</small></span></span>)}</div>
          <p className="impact-y-label">↑ Graduates attending any college by March 2026 (%)</p>
          <div className="impact-scatter-canvas" aria-hidden="true">
            <ResponsiveContainer width="100%" height="100%">
              <ScatterChart margin={{top:12,right:15,bottom:10,left:0}}>
                <CartesianGrid stroke="#dcded6" strokeDasharray="3 5"/>
                <XAxis type="number" dataKey="fafsaPct" name="School FAFSA ratio" domain={[0,100]} ticks={[0,25,50,75,100]} tickFormatter={v=>`${v}%`} tick={{fontSize:12,fill:'#4f6268'}} tickLine={false} tickMargin={8}/>
                <YAxis type="number" dataKey="collegeAttendancePct" name="College attendance" domain={[0,100]} ticks={[0,25,50,75,100]} tickFormatter={v=>`${v}%`} tick={{fontSize:12,fill:'#4f6268'}} tickLine={false} width={45}/>
                <Tooltip content={<SchoolTooltip/>} cursor={{strokeDasharray:'3 3'}}/>
                {groups.map(group=><Scatter key={group.id} name={group.label} data={rows.filter(r=>r.ses3===group.id)} fill={group.color} fillOpacity={.65} stroke={group.color} strokeWidth={.4} isAnimationActive={false}/>)}
              </ScatterChart>
            </ResponsiveContainer>
          </div>
          <p className="research-value-axis-title">School FAFSA ratio through May 31, 2025 (%) →</p>
          <p className="research-chart-footnote">FAFSA ratio = completed applications ÷ October 2024 seniors × 100. College attendance includes two- and four-year institutions. The measures cover different administrative populations. Dots show observed values; the regression result includes controls.</p>
        </figure>
        <TableDisclosure label={`View all ${rows.length} schools behind this chart`}><table className="data-table"><caption>Observed FAFSA ratios and college attendance, Class of 2025</caption><thead><tr><th scope="col">School</th><th scope="col">Low-income proportion</th><th scope="col">FAFSA ratio</th><th scope="col">College attendance</th></tr></thead><tbody>{rows.map(r=><tr key={r.schoolCode}><th scope="row">{r.schoolName}</th><td>{number(r.lowIncomePct)}%</td><td>{number(r.fafsaPct)}%</td><td>{number(r.collegeAttendancePct)}%</td></tr>)}</tbody></table></TableDisclosure>
        <a className="chart-download" href="./downloads/fafsa-and-college-attendance-356-schools.csv" download><DownloadSimple size={17} aria-hidden="true"/>Download chart data</a>
        <p className="research-chart-footnote">Sources: audited Federal Student Aid and Massachusetts DESE exports. 51 of the 407 eligible schools do not have both usable measures.</p>
      </div>
      <aside className="impact-result">
        <span className="evidence-tag">Adjusted regression result</span>
        <p className="impact-stat">{signed(estimate.b,1)}<span>percentage points</span></p>
        <h3>Higher FAFSA ratios are associated with higher college attendance.</h3>
        <p>After accounting for measured school characteristics, a 10-point higher FAFSA ratio is associated with {number(estimate.b)} percentage points higher college attendance.</p>
        <dl className="impact-model-facts"><div><dt>95% confidence interval</dt><dd>{signed(estimate.ci_low,1)} to {signed(estimate.ci_high,1)} points</dd></div><div><dt>Statistical evidence</dt><dd>p &lt; 0.001</dd></div><div><dt>Sample</dt><dd>{estimate.n} schools · {estimate.n_clusters} districts</dd></div></dl>
        <details><summary>Controls and verification</summary><p>OLS model C_plus_F includes low-income proportion, log grades 9–12 enrollment, school type, English learner proportion, and students with disabilities proportion. Standard errors are clustered by district. Campus-tract income is not included.</p><p>The Stata export was independently verified in Python. This 356-school model differs from the 355-school income-to-FAFSA models below.</p><a className="evidence-source" href="./downloads/fafsa-college-evidence.json" download>Download the model and validation record</a></details>
        <p className="impact-limit"><strong>Association, not a program effect.</strong> College plans and other unmeasured factors may influence both outcomes. The estimate cannot predict what an assistance program would achieve.</p>
      </aside>
    </div>
    <div className="evidence-bridge">
      <div><span className="evidence-tag">External randomized study · 2008 intervention</span><h3>An experiment found benefits from application help</h3><p>FAFSA assistance with personalized aid information increased next-year college enrollment by <strong>8.1 percentage points</strong> among dependent participants from low-income households. Information alone did not produce comparable improvements.</p><p className="note">This supports assistance near college entry. It does not test middle-school instruction or predict a local program’s impact.</p><details><summary>Study details</summary><p>The 2008 experiment was conducted in Ohio and the Charlotte area. Enrollment rose from 34.2% to 42.3% (p = 0.019). Bettinger and colleagues published the study in QJE in 2012.</p></details><EvidenceSource href={SOURCES.assistance}>Read the randomized study · Table III</EvidenceSource></div>
      <div className="evidence-bridge-action"><p className="eyebrow">From evidence to action</p><h3>What schools could do</h3><p>Introduce financial-aid education in middle school, continue it in high school, and offer individual application help. The early start is a proposal to evaluate.</p><a className="button" href="#/actions">Read the recommendations<ArrowRight size={21} aria-hidden="true"/></a></div>
    </div>
  </section>;
}
