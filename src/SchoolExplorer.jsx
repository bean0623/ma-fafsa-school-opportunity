import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { X, ArrowLeft, ArrowRight, DownloadSimple, Plus, Minus } from '@phosphor-icons/react';
import { CartesianGrid, ResponsiveContainer, Scatter, ScatterChart, Tooltip, XAxis, YAxis } from 'recharts';
import './SchoolExplorer.css';

const SES_LABELS = { 1: 'Higher proportion (59.8–95.8%)', 2: 'Middle proportion (28.9–59.5%)', 3: 'Lower proportion (5.1–28.6%)' };
const STATUS_LABELS = {
  usable: 'Usable screened estimate',
  suppressed: 'Suppressed in the federal source',
  unresolved_multiple_records: 'Unresolved multiple source records',
  population_mismatch_over_100: 'Screened out: applicant-to-senior ratio above 100%',
  unavailable_or_unmatched: 'Unavailable or unmatched',
};
const hasNumber = value => typeof value === 'number' && Number.isFinite(value);
const percent = value => hasNumber(value) ? `${value.toFixed(1)}%` : '—';
const integer = value => hasNumber(value) ? value.toLocaleString('en-US', { maximumFractionDigits: 0 }) : '—';
const dollars = value => value === 250001 ? '$250,000+' : hasNumber(value) ? value.toLocaleString('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }) : '—';
const normalized = value => String(value ?? '').normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase();

function Modal({ title, children, onClose, wide = false }) {
  const panelRef = useRef(null);
  const titleId = useId();
  useEffect(() => {
    const previousFocus = document.activeElement;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const panel = panelRef.current;
    panel?.querySelector('button')?.focus();
    const handleKey = event => {
      if (event.key === 'Escape') { event.preventDefault(); onClose(); return; }
      if (event.key !== 'Tab' || !panel) return;
      const controls = [...panel.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), [tabindex="0"]')];
      const first = controls[0];
      const last = controls[controls.length - 1];
      if (!first) { event.preventDefault(); panel.focus(); return; }
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', handleKey);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener('keydown', handleKey);
      if (previousFocus?.isConnected) previousFocus.focus();
    };
  }, [onClose]);
  if (typeof document === 'undefined') return null;
  return createPortal(
    <div className="detail-overlay se-overlay" onMouseDown={event => { if (event.target === event.currentTarget) onClose(); }}>
      <section className={`detail-panel se-dialog${wide ? ' se-dialog-wide' : ''}`} role="dialog" aria-modal="true" aria-labelledby={titleId} ref={panelRef} tabIndex={-1}>
        <div className="se-dialog-head">
          <div><p className="eyebrow">School explorer</p><h2 id={titleId}>{title}</h2></div>
          <button className="se-close" type="button" onClick={onClose} aria-label="Close dialog"><X size={22}/></button>
        </div>
        {children}
      </section>
    </div>, document.body,
  );
}

function SchoolMetrics({ school }) {
  const metrics = [
    ['Low-income students (%)', percent(school.lowIncomePct)],
    ['Screened FAFSA estimate', percent(school.fafsaPct)],
    ['Enrolled grade-12 students', integer(school.grade12Enrollment)],
    ['Four-year college attendance, estimated', percent(school.fourYearCollegePct)],
    ['Severe chronic absence', percent(school.severeAbsencePct)],
    ['Campus-tract median household income', dollars(school.campusIncome)],
  ];
  return <dl className="se-metrics">{metrics.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>;
}

function ScatterTooltip({ active, payload }) {
  const school = payload?.[0]?.payload;
  if (!active || !school) return null;
  return <div className="se-tooltip"><strong>{school.name}</strong><span>{school.isBps ? 'Boston Public Schools' : school.district}</span><span>Low-income students: {percent(school.lowIncomePct)}</span><span>FAFSA estimate: {percent(school.fafsaPct)}</span></div>;
}

function downloadSchools(schools) {
  const headers = ['school_code', 'school_name', 'district', 'school_type', 'boston_public_schools', 'student_low_income_pct', 'statewide_low_income_group', 'fafsa_screened_estimate_pct', 'fafsa_availability', 'grade12_enrollment_2024_25', 'four_year_college_estimate_pct', 'severe_absence_pct', 'campus_tract_household_income', 'fafsa_cutoff', 'fafsa_aid_cycle'];
  const csvCell = value => value === null || value === undefined ? '' : `"${String(value).replaceAll('"', '""')}"`;
  const rows = schools.map(s => [s.schoolCode, s.name, s.district, s.schoolType, s.isBps ? 'Yes' : 'No', s.lowIncomePct, SES_LABELS[s.ses3], s.fafsaPct, STATUS_LABELS[s.fafsaStatus] || 'Unavailable', s.grade12Enrollment, s.fourYearCollegePct, s.severeAbsencePct, s.campusIncome, '2025-05-31', '2025-26']);
  const csv = '\uFEFF' + [headers, ...rows].map(row => row.map(csvCell).join(',')).join('\r\n');
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = 'massachusetts-school-explorer-filtered.csv';
  document.body.appendChild(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function SchoolExplorer({ data }) {
  const schools = useMemo(() => (data?.schools ?? []).filter(s => s.eligible !== false), [data]);
  const [search, setSearch] = useState('');
  const [geography, setGeography] = useState('statewide');
  const [ses, setSes] = useState('all');
  const [availability, setAvailability] = useState('all');
  const [sort, setSort] = useState('name-asc');
  const [pageSize, setPageSize] = useState(20);
  const [page, setPage] = useState(1);
  const [detailCode, setDetailCode] = useState(null);
  const [compareCodes, setCompareCodes] = useState([]);
  const [showComparison, setShowComparison] = useState(false);
  const [showChart, setShowChart] = useState(false);
  const [announcement, setAnnouncement] = useState('');
  const closeDetail = useCallback(() => setDetailCode(null), []);
  const closeComparison = useCallback(() => setShowComparison(false), []);
  const filtered = useMemo(() => {
    const terms = normalized(search).trim().split(/\s+/).filter(Boolean);
    const result = schools.filter(school => {
      const searchable = normalized(`${school.name} ${school.district} ${school.schoolCode}`);
      return terms.every(term => searchable.includes(term))
        && (geography !== 'bps' || school.isBps)
        && (ses === 'all' || school.ses3 === Number(ses))
        && (availability === 'all' || (availability === 'usable' ? school.fafsaUsable : !school.fafsaUsable));
    });
    const [field, direction] = sort.split('-');
    return result.sort((a, b) => {
      if (field === 'name') return (direction === 'asc' ? 1 : -1) * a.name.localeCompare(b.name);
      const key = field === 'lowIncome' ? 'lowIncomePct' : 'fafsaPct';
      const av = a[key]; const bv = b[key];
      if (!hasNumber(av) && !hasNumber(bv)) return a.name.localeCompare(b.name);
      if (!hasNumber(av)) return 1;
      if (!hasNumber(bv)) return -1;
      return ((direction === 'asc' ? 1 : -1) * (av - bv)) || a.name.localeCompare(b.name);
    });
  }, [schools, search, geography, ses, availability, sort]);
  useEffect(() => { setPage(1); }, [search, geography, ses, availability, sort, pageSize]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const displayed = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);
  const schoolByCode = useMemo(() => new Map(schools.map(s => [s.schoolCode, s])), [schools]);
  const detail = schoolByCode.get(detailCode);
  const compared = compareCodes.map(code => schoolByCode.get(code)).filter(Boolean);
  const plotted = useMemo(() => filtered.filter(s => hasNumber(s.lowIncomePct) && hasNumber(s.fafsaPct)), [filtered]);
  const otherPoints = useMemo(() => plotted.filter(s => !s.isBps), [plotted]);
  const bpsPoints = useMemo(() => plotted.filter(s => s.isBps), [plotted]);
  const toggleComparison = school => {
    setCompareCodes(previous => previous.includes(school.schoolCode) ? previous.filter(code => code !== school.schoolCode) : previous.length < 3 ? [...previous, school.schoolCode] : previous);
  };
  const reset = () => { setSearch(''); setGeography('statewide'); setSes('all'); setAvailability('all'); setSort('name-asc'); setPage(1); };
  const rangeStart = filtered.length ? (currentPage - 1) * pageSize + 1 : 0;
  const rangeEnd = Math.min(currentPage * pageSize, filtered.length);

  return <div className="school-explorer">
    <header className="page-head">
      <p className="eyebrow">The school explorer</p>
      <h1>Compare schools</h1>
      <p className="lede">Search {schools.length} Massachusetts schools and compare their student populations, FAFSA estimates and education outcomes.</p>
      <p className="note">These are school-level observations, not a school ranking. The merged sample is not a statewide census.</p>
    </header>

    <section className="section se-explorer-section" aria-labelledby="se-explore-heading">
      <div className="se-section-heading"><h2 id="se-explore-heading">Explore the sample</h2><button className="button se-download" type="button" disabled={!filtered.length} onClick={() => { downloadSchools(filtered); setAnnouncement(`Downloaded ${filtered.length} schools as CSV.`); }}>Download filtered CSV <DownloadSimple size={20} aria-hidden="true"/></button></div>
      <div className="filters se-filters">
        <label className="se-search">School, district, or school code<input type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder="Search schools…" /></label>
        <label>Geography<select value={geography} onChange={event => setGeography(event.target.value)}><option value="statewide">All Massachusetts</option><option value="bps">Boston Public Schools</option></select></label>
        <label>Low-income students (%)<select value={ses} onChange={event => setSes(event.target.value)}><option value="all">All three groups</option>{[1, 2, 3].map(id => <option key={id} value={id}>{SES_LABELS[id]}</option>)}</select></label>
        <label>FAFSA estimate<select value={availability} onChange={event => setAvailability(event.target.value)}><option value="all">All availability</option><option value="usable">Usable estimate</option><option value="unavailable">Unavailable / screened out</option></select></label>
      </div>
      <div className="se-table-tools">
        <p role="status" aria-live="polite"><strong>{filtered.length}</strong> of {schools.length} schools · {plotted.length} with usable FAFSA estimates</p>
        <div><button className="se-text-button" type="button" onClick={reset}>Reset filters</button><label className="se-sort">Sort by<select value={sort} onChange={event => setSort(event.target.value)}><option value="name-asc">School name A–Z</option><option value="name-desc">School name Z–A</option><option value="lowIncome-asc">Low-income proportion: low to high</option><option value="lowIncome-desc">Low-income proportion: high to low</option><option value="fafsa-asc">FAFSA estimate: low to high</option><option value="fafsa-desc">FAFSA estimate: high to low</option></select></label></div>
      </div>
      {compared.length > 0 && <div className="se-comparison-bar"><div><strong>Selected for comparison</strong><div className="se-selected-schools">{compared.map(s => <button type="button" key={s.schoolCode} onClick={() => toggleComparison(s)} aria-label={`Remove ${s.name} from comparison`}>{s.name}<X size={15} aria-hidden="true"/></button>)}</div></div><button className="button" type="button" disabled={compared.length < 2} onClick={() => setShowComparison(true)}>Compare {compared.length} schools</button></div>}

      <div className="se-table-scroll" id="explorer-school-table" tabIndex={0} role="region" aria-label="School results table; scroll horizontally for all columns">
        <table className="data-table se-school-table"><caption className="se-sr-only">Filtered schools. Select a school name for its details. Select up to three comparison checkboxes. Missing estimates are shown as an em dash.</caption><thead><tr><th scope="col">Compare</th><th scope="col" aria-sort={sort.startsWith('name-') ? (sort.endsWith('asc') ? 'ascending' : 'descending') : undefined}>School</th><th scope="col">Geography</th><th scope="col" aria-sort={sort.startsWith('lowIncome-') ? (sort.endsWith('asc') ? 'ascending' : 'descending') : undefined}>Low-income proportion</th><th scope="col" aria-sort={sort.startsWith('fafsa-') ? (sort.endsWith('asc') ? 'ascending' : 'descending') : undefined}>FAFSA estimate</th><th scope="col">Grade-12 students</th></tr></thead><tbody>
          {displayed.map(school => <tr key={school.schoolCode}><td><input type="checkbox" checked={compareCodes.includes(school.schoolCode)} disabled={compareCodes.length >= 3 && !compareCodes.includes(school.schoolCode)} onChange={() => toggleComparison(school)} aria-label={`Compare ${school.name}`} /></td><th scope="row"><button className="se-school-link" type="button" onClick={() => setDetailCode(school.schoolCode)}>{school.name}</button><span className="se-school-subline">{school.schoolType} · {school.schoolCode}</span></th><td>{school.isBps ? <span className="se-bps-badge">Boston Public Schools</span> : 'Other Massachusetts'}</td><td>{percent(school.lowIncomePct)}<span className="se-school-subline">{SES_LABELS[school.ses3]}</span></td><td>{percent(school.fafsaPct)}{!hasNumber(school.fafsaPct) && <span className="se-school-subline">Not available</span>}</td><td>{integer(school.grade12Enrollment)}</td></tr>)}
          {!displayed.length && <tr><td colSpan={6}><div className="se-empty"><h3>No schools match these filters.</h3><p>{geography === 'bps' && ses === '3' ? 'No Boston schools in this sample fall in the group with 5.1–28.6% low-income students.' : 'Try a broader search or another group.'}</p><button className="button" type="button" onClick={reset}>Reset filters</button></div></td></tr>}
        </tbody></table>
      </div>
      <div className="se-pagination"><span>Showing {rangeStart}–{rangeEnd} of {filtered.length} schools</span><label>Rows per page<select value={pageSize} onChange={event => setPageSize(Number(event.target.value))}><option value={15}>15</option><option value={20}>20</option><option value={40}>40</option></select></label><nav aria-label="School results pages"><button type="button" className="button" disabled={currentPage <= 1} onClick={() => setPage(currentPage - 1)}><ArrowLeft size={16} aria-hidden="true"/> Previous</button><span>Page {currentPage} of {totalPages}</span><button type="button" className="button" disabled={currentPage >= totalPages} onClick={() => setPage(currentPage + 1)}>Next <ArrowRight size={16} aria-hidden="true"/></button></nav></div>
      <p className="note se-table-note">Select up to three schools to compare. An em dash means unavailable, not zero. FAFSA estimates divide completions through May 31, 2025 for the 2025–26 aid cycle by October 2024 grade-12 enrollment; these screened ratios do not match individual students.</p>

      <div className="se-relationship"><button className="se-chart-toggle" type="button" aria-expanded={showChart} aria-controls="se-relationship-chart" onClick={() => setShowChart(value => !value)}><span>Low-income students (%) and FAFSA estimates</span><span aria-hidden="true">{showChart ? <Minus size={20}/> : <Plus size={20}/>}</span></button><div id="se-relationship-chart" hidden={!showChart}>{showChart && <div className="chart-panel se-scatter-panel"><h3 className="research-chart-title">Low-income students (%) and school FAFSA completion</h3><p className="research-chart-subtitle">Class of 2025 · FAFSA through May 31, 2025 · {plotted.length} schools with usable ratios in the current selection</p><p>The chart follows the filters above. Each dot is one school; the table provides the same school-level values.</p>{plotted.length ? <><div className="se-chart-legend"><span><i style={{ background: '#386e75' }} />Other Massachusetts schools</span><span><i style={{ background: '#b33f32' }} />Boston Public Schools</span></div><div className="se-scatter" role="img" aria-label={`Scatterplot of low-income proportion and screened FAFSA estimate for ${plotted.length} matching schools. The table above contains accessible school-level values.`}><ResponsiveContainer width="100%" height={340}><ScatterChart margin={{ top: 16, right: 24, bottom: 32, left: 10 }}><CartesianGrid stroke="#dce0dd" strokeDasharray="3 3" /><XAxis type="number" dataKey="lowIncomePct" domain={[0, 100]} name="Low-income students (%)" unit="%" label={{ value: 'Low-income students (%)', position: 'bottom', offset: 12 }} tick={{ fontSize: 12 }} /><YAxis type="number" dataKey="fafsaPct" domain={[0, 100]} name="FAFSA estimate" unit="%" label={{ value: 'FAFSA estimate (%)', angle: -90, position: 'insideLeft', offset: 6 }} tick={{ fontSize: 12 }} /><Tooltip content={<ScatterTooltip />} cursor={{ strokeDasharray: '3 3' }} /><Scatter name="Other Massachusetts" data={otherPoints} fill="#386e75" fillOpacity={0.65} isAnimationActive={false} /><Scatter name="Boston Public Schools" data={bpsPoints} fill="#b33f32" fillOpacity={0.9} isAnimationActive={false} /></ScatterChart></ResponsiveContainer></div></> : <p className="se-empty">No usable FAFSA estimates match the current filters.</p>}<p className="note">The relationship describes school composition and screened estimates. It does not identify a causal effect.</p></div>}</div></div>
    </section>
    <span className="se-sr-only" role="status" aria-live="polite">{announcement}</span>

    {detail && <Modal title={detail.name} onClose={closeDetail}><p className="se-detail-context">{detail.isBps ? 'Boston Public Schools' : detail.district} · {detail.schoolType}<br />School code {detail.schoolCode} · Grades {detail.grades || 'not reported'}</p><span className="se-group-tag">{SES_LABELS[detail.ses3]}</span><SchoolMetrics school={detail} /><div className="se-definition"><h3>Reading these values</h3><p><strong>FAFSA:</strong> {STATUS_LABELS[detail.fafsaStatus] || 'Not available'}. Screened completions through May 31, 2025 (2025–26 aid) divided by October 2024 enrolled seniors. Federal applicants and enrolled seniors can differ.</p><p><strong>Four-year college:</strong> approximate share of Class of 2025 graduates attending a four-year college by March 2026, derived from rounded reported percentages.</p><p><strong>Severe absence:</strong> share missing at least 20% of membership days, across the whole school in 2024–25.</p><p><strong>Campus income:</strong> the school location’s tract median household-income estimate; it does not describe students’ home neighborhoods. ACS vintage and geocoding provenance remain unresolved.{detail.campusIncome === 250001 ? ' The source top-code is shown as $250,000+, rather than an exact household income.' : ''}{hasNumber(detail.campusLocationCount) && detail.campusLocationCount > 1 ? ` This school combines ${detail.campusLocationCount} campus locations; its income value averages the campus-tract estimates.` : ''}</p><p>Groups use fixed statewide whole-school low-income proportions. These comparisons do not measure school quality or individual student circumstances.</p></div><button className="button" type="button" disabled={compareCodes.length >= 3 && !compareCodes.includes(detail.schoolCode)} onClick={() => toggleComparison(detail)}>{compareCodes.includes(detail.schoolCode) ? 'Remove from comparison' : 'Add to comparison'}</button></Modal>}
    {showComparison && <Modal title="Compare school context" onClose={closeComparison} wide><p className="note">Side-by-side context for your selected schools. Measures describe different populations and periods; they do not rank school quality. An em dash means unavailable.</p><div className="se-compare-grid" style={{ '--compare-columns': compared.length }}>{compared.map(school => <article key={school.schoolCode}><span className="se-group-tag">{school.isBps ? 'Boston Public Schools' : 'Other Massachusetts'}</span><h3>{school.name}</h3><p>{SES_LABELS[school.ses3]}</p><SchoolMetrics school={school} /><p className="note">FAFSA: {STATUS_LABELS[school.fafsaStatus] || 'Not available'}.</p></article>)}</div><p className="note">FAFSA: May 31, 2025 cutoff / October 2024 seniors. Four-year college: Class of 2025, March 2026 follow-up, derived from rounded rates. Severe absence: whole-school 2024–25 population. Campus income describes school location, with unresolved ACS provenance.</p></Modal>}
  </div>;
}
