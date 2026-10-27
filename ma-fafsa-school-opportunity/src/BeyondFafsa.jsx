import React, { useState } from 'react';
import { ArrowRight, ArrowUpRight, DownloadSimple } from '@phosphor-icons/react';
import { GroupBars, GeographyToggle, TableDisclosure, GROUPS, number, signed, interval, pValue } from './charts';
import './beyond.css';

const RESOURCES = {
  attendanceStudy: 'https://ies.ed.gov/use-work/resource-library/report/impact-study/getting-students-track-graduation-impacts-early-warning-intervention-and-monitoring-system-after-one',
  attendancePractice: 'https://www.bostonpublicschools.org/bps-departments/opportunity-youth/attendance',
  advisingStudy: 'https://ies.ed.gov/ncee/wwc/Docs/InterventionReports/WWC_IR_Bottom-Line_REPORT_508.pdf',
  advisingPractice: 'https://www.doe.mass.edu/ccte/sec-design/mycap/default.html',
  summerReview: 'https://ies.ed.gov/ncee/wwc/EvidenceSnapshot/693'
};
const PRIORITIES = [
  {
    id: 'att_chronic_abs_20pct',
    title: 'Reduce severe absence.',
    chartTitle: 'Students missing at least one-fifth of school',
    axis: 'Students missing at least 20% of membership days (%)',
    period: '2024–25 · All grades at each school',
    measureNote: 'This measures severe absence across the whole school, including any younger grades. It is not restricted to seniors.',
    fafsaConnection: 'Pair attendance outreach with flexible FAFSA appointments and family follow-up, so students approaching graduation can access aid guidance even when they miss school.',
    fafsaLimit: 'A proposed response: these results do not establish a link between severe absence and FAFSA completion.',
    actionTitle: 'Respond early and address the reason.',
    actions: ['Give an attendance team protected time to review recurring absences and course progress.', 'Ask students and families about barriers, then coordinate relevant transport, health or academic support.', 'Assign one adult to follow up and check whether attendance improves.'],
    track: 'Track absence at both the 10% and 20% thresholds, support received and course completion.',
    evidence: 'A randomized study of 73 high schools found that an early-warning and support system reduced chronic absence and course failure after one year.',
    limit: 'The study used a 10% absence threshold. It does not predict the reduction in our 20% measure or establish a graduation effect.',
    links: [['Read the attendance experiment', 'Research · IES / REL Midwest', 'attendanceStudy'], ['Use Boston’s attendance resources', 'Practice · BPS Tiered Attendance System', 'attendancePractice']]
  },
  {
    id: 'ma06_college4_grad',
    title: 'Support the transition to college.',
    chartTitle: 'Estimated four-year college attendance',
    axis: 'Estimated graduates attending a four-year college (%)',
    period: 'Class of 2025 · Attendance by March 2026',
    measureNote: 'An approximate rate among graduates, calculated from rounded attendance and college-sector percentages.',
    fafsaConnection: 'FAFSA can open access to aid for eligible students pursuing four-year college, and our school data link higher FAFSA ratios to higher overall college attendance.',
    fafsaLimit: 'The existing FAFSA regression covers all colleges; it does not show how much four-year attendance would rise if completion increased.',
    actionTitle: 'Keep an adviser involved through enrollment.',
    actions: ['Give students a named adviser to discuss course choices, college fit and affordable options.', 'Keep help available after graduation for placement tests, orientation, housing and registration.', 'Connect students with support at their next institution and follow up during the first year.'],
    track: 'Track advising reach, completed enrollment steps, enrollment and persistence across all pathways.',
    evidence: 'A randomized evaluation of Bottom Line, including Boston and Worcester, found benefits from intensive advising. The What Works Clearinghouse rates its enrollment evidence as potentially positive.',
    limit: 'This was a package of college-choice, financial-aid and ongoing support for eligible applicants. It does not isolate advising from aid help or predict effects for every school.',
    links: [['Read the advising evaluation', 'Research · What Works Clearinghouse (PDF)', 'advisingStudy'], ['Use Massachusetts MyCAP guidance', 'Practice · College and career planning', 'advisingPractice']]
  }
];

function ResourceLink({title,description,href}) {
  return <a className="beyond-resource" href={href} target="_blank" rel="noreferrer"><span><strong>{title}</strong><small>{description}</small></span><ArrowUpRight size={19} aria-hidden="true"/></a>;
}

function Priority({item,data,geography,index}) {
  const rows = data.outcomes.groups.filter(row=>row.outcome===item.id && row.geography===geography).sort((a,b)=>a.sesGroup-b.sesGroup);
  const model = data.outcomes.sesResults.find(row=>row.outcome===item.id && row.specification==='income_adj' && row.geography==='Statewide');
  const high=rows.find(row=>row.sesGroup===1), compare=rows.find(row=>row.sesGroup===(geography==='BPS'?2:3));
  const absence=item.id==='att_chronic_abs_20pct';
  return <article className="beyond-priority" aria-labelledby={`priority-${item.id}`}>
    <header><p className="eyebrow">Priority {String(index+1).padStart(2,'0')}</p><h2 id={`priority-${item.id}`}>{item.title}</h2></header>
    <GroupBars rows={rows} countKey="nAvailable" title={item.chartTitle} subtitle={`${geography==='BPS'?'Boston Public Schools':'Massachusetts school sample'} · ${item.period}`} axisLabel={item.axis} showFootnote={false}/>
    <p className="beyond-finding">{absence?'Average severe absence is':'Estimated four-year attendance averages'} <strong>{number(high?.mean)}%</strong> in schools with the largest low-income proportion, compared with <strong>{number(compare?.mean)}%</strong> in the {geography==='BPS'?'middle group':'group with the smallest proportion'}.</p>
    <p className="note beyond-measure">{item.measureNote}</p>
    <aside className="beyond-fafsa-connection" aria-label={`Connection to FAFSA: ${item.title}`}><p className="eyebrow">Connection to FAFSA</p><p>{item.fafsaConnection}</p><p className="note">{item.fafsaLimit}</p><a href="#/findings">Why FAFSA matters<ArrowRight size={15}/></a></aside>
    <TableDisclosure label="View chart data"><table className="data-table"><caption>{item.chartTitle} · Unweighted school means</caption><thead><tr><th scope="col">Low-income proportion</th><th scope="col">Reporting schools</th><th scope="col">Average</th></tr></thead><tbody>{rows.map(row=><tr key={row.sesGroup}><th scope="row">{GROUPS[row.sesGroup]}</th><td>{row.nAvailable}</td><td>{Number.isFinite(row.mean)?`${number(row.mean)}%`:'No schools'}</td></tr>)}</tbody></table><a className="chart-download" href="./downloads/06_outcomes_by_ses.csv" download><DownloadSimple size={17}/>Download outcome comparisons</a></TableDisclosure>
    <section className="beyond-action" aria-labelledby={`action-${item.id}`}><p className="eyebrow">What schools can do</p><h3 id={`action-${item.id}`}>{item.actionTitle}</h3><ol>{item.actions.map(action=><li key={action}>{action}</li>)}</ol><p className="beyond-track"><strong>Check progress:</strong> {item.track}</p></section>
    <div className="beyond-evidence"><p className="eyebrow">Evidence for action</p><p>{item.evidence}</p><p className="note">{item.limit}</p>
      <details><summary>Study details and limits</summary>{absence?<p>In the 2014–15 trial, 37,671 first- and second-year students attended 73 high schools in three Midwest states. Absence of at least 10% was 10% in intervention schools versus 14% in controls; course failure was 21% versus 26%. The trial did not establish an effect on on-time graduation.</p>:<><p>The 2021 review covers a randomized study of 2,422 applicants in Boston, Worcester and New York City, from the graduating classes of 2015 and 2016. Eligibility included family income below 200% of federal poverty guidelines and a high-school GPA of at least 2.5. Four-year enrollment was 80.6% in the intervention group and 70.3% in the comparison group.</p><p>Evidence on summer counseling more broadly is mixed for enrollment. Schools should evaluate their own implementation and who it reaches. <a href={RESOURCES.summerReview} target="_blank" rel="noreferrer">Read the WWC summer-counseling review ↗</a></p></>}</details>
    </div>
    <div className="beyond-resources">{item.links.map(([title,description,key])=><ResourceLink key={key} title={title} description={description} href={RESOURCES[key]}/>)}</div>
    {model && <details className="beyond-model"><summary>Statewide adjusted association</summary><p><strong>{signed(model.estimate)} percentage points</strong> per 10-point increase in low-income proportion; nominal 95% CI: {interval(model)}. Holm-adjusted p: {pValue(model.pHolmGlobal)}. {number(model.n,0)} schools in {number(model.nClusters,0)} districts.</p><p>The model controls for school size, school type, English-learner and disability proportions, and exploratory campus income. Standard errors are clustered by district. It tests a continuous association, not each pair of groups or the effect of the proposed action.</p><a href="./downloads/06_ses_results.csv" download className="chart-download"><DownloadSimple size={17}/>Download adjusted results</a></details>}
  </article>;
}

export function BeyondFafsa({data}) {
  const [geography,setGeography]=useState('Statewide');
  return <article className="beyond-page">
    <header className="page-head"><p className="eyebrow">Beyond FAFSA</p><h1>Attendance and<br/>the path to college.</h1><p className="lede">Students need support throughout school and the transition after graduation. These two outcomes show where schools could focus that support.</p></header>
    <section className="section beyond-main" aria-label="Two priorities for school support"><div className="beyond-intro"><div><h2>Two priorities for action</h2><p>Compare the same three school groups, then see practical responses and the research behind them.</p></div><GeographyToggle value={geography} onChange={setGeography} label="Choose geography for both outcome charts"/></div>
      <p className="note beyond-chart-note">Bars show averages across reporting schools, with each school weighted equally. Groups use fixed statewide low-income proportions; missing outcomes are excluded.</p>
      {geography==='BPS' && <p className="beyond-boston-note" role="status"><strong>A small Boston comparison:</strong> the middle group contains only four schools, including three exam schools. No Boston schools fall in the lower-proportion group. The adjusted estimates below describe the statewide sample.</p>}
      <div className="beyond-grid">{PRIORITIES.map((item,index)=><Priority key={item.id} item={item} data={data} geography={geography} index={index}/>)}</div>
      <div className="beyond-interpretation"><p><strong>Use the gaps to identify priorities, not to predict policy effects.</strong> Both outcomes remain associated with low-income proportion in the statewide adjusted models after a correction for testing 33 outcomes. The school comparisons do not establish what causes the gaps.</p><p>Four-year college is one possible pathway. Advising should support students’ goals across two-year colleges, training, apprenticeships and other options.</p>
      <details><summary>Why these outcomes, and what remains uncertain?</summary><p>These priorities combine interpretable measures, visible differences and relevant intervention research. The complete set of 33 outcomes remains available, including uncertain findings. AP exam counts are not validated participation rates, and the MCAS grade and subgroup filters still need confirmation.</p><p>The campus-income control is exploratory: its ACS year and geographic matching need verification, and a school’s location does not necessarily represent its students’ neighborhoods. Holm p-values adjust across 33 outcomes within each specification and geography; 95% confidence intervals are nominal.</p><p>Program evaluation would need information on who received support, when it started and outcomes over time. These data do not measure attendance barriers or advising exposure. MyCAP and BPS resources help with implementation; they are not impact evaluations.</p></details></div>
      <div className="beyond-next"><a className="button" href="#/outcomes">Explore all 33 outcomes<ArrowRight size={20}/></a><a className="text-link" href="#/methods">Read the methods<ArrowRight size={18}/></a></div>
    </section>
  </article>;
}
