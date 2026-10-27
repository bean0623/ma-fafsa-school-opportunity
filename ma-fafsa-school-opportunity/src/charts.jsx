import React, { useEffect, useId, useRef, useState } from 'react';
import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Cell, LabelList, ReferenceLine } from 'recharts';
import { DownloadSimple } from '@phosphor-icons/react';
import './charts.css';

export const GROUPS = { 1: 'Higher proportion', 2: 'Middle proportion', 3: 'Lower proportion' };
const COLORS = { 1: 'var(--ses-high, #B77756)', 2: 'var(--ses-mid, #7B9694)', 3: 'var(--ses-low, #183D50)' };
const FULL_GROUPS = GROUPS;
const GROUP_RANGES = { 1: '59.8–95.8%', 2: '28.9–59.5%', 3: '5.1–28.6%' };
export const number = (value, digits = 1) => Number.isFinite(value) ? value.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits }) : '—';
export const signed = (value, digits = 2) => Number.isFinite(value) ? `${value > 0 ? '+' : ''}${number(value, digits)}` : '—';
export const pValue = (value) => !Number.isFinite(value) ? '—' : value < .0001 ? '<0.0001' : value.toFixed(value < .001 ? 4 : 3);
export const interval = (row) => `${number(row.ciLow, 2)} to ${number(row.ciHigh, 2)}`;

function useChartWidth() {
  const ref = useRef(null);
  const [width, setWidth] = useState(600);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => {
      const next = element.getBoundingClientRect().width;
      if (next > 0) setWidth(Math.round(next));
    };
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return [ref, width];
}

function groupRange(row) {
  return Number.isFinite(row.lowIncomeMin) && Number.isFinite(row.lowIncomeMax)
    ? `${number(row.lowIncomeMin)}–${number(row.lowIncomeMax)}%`
    : GROUP_RANGES[row.sesGroup];
}

function CategoryTick({ x, y, payload, rows, compact, valueKey }) {
  const row = rows.find(item => item.name === payload.value);
  if (!row) return null;
  let sample = `N = ${number(row.count, 0)} reporting schools`;
  if (valueKey === 'schoolCoveragePct') sample = `${number(row.nUsable, 0)} / ${number(row.nEligible, 0)} schools`;
  if (valueKey === 'seniorSchoolCoveragePct') sample = `${number(row.seniorsInUsableSchools, 0)} / ${number(row.seniorsTotal, 0)} seniors`;
  if (row.nEligible === 0) sample = 'No schools in this group';
  else if (!Number.isFinite(row.value)) sample = 'No usable estimate';
  return <text x={x - 7} y={y} textAnchor="end" className="research-category-tick">
    <tspan x={x - 7} dy="-17" fontSize={compact ? 11.5 : 13.5} fontWeight="600" fill="#183d50">{FULL_GROUPS[row.sesGroup]}</tspan>
    <tspan x={x - 7} dy="19" fontSize={compact ? 11.5 : 12.5} fill="#4f6268">{groupRange(row)}</tspan>
    <tspan x={x - 7} dy="18" fontSize={compact ? 10.2 : 11.5} fill="#4f6268">{sample}</tspan>
  </text>;
}

export function downloadCSV(rows, filename) {
  if (!rows.length) return;
  const fields = [...new Set(rows.flatMap(row => Object.keys(row)))];
  const quote = value => `"${String(value == null ? '' : Array.isArray(value) ? value.join('; ') : value).replaceAll('"', '""')}"`;
  const csv = [fields.map(quote).join(','), ...rows.map(row => fields.map(key => quote(row[key])).join(','))].join('\r\n');
  const url = URL.createObjectURL(new Blob(['\uFEFF', csv], { type: 'text/csv;charset=utf-8;' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function DownloadCSV({ rows, filename, children = 'Download chart data' }) {
  return <button type="button" className="chart-download" onClick={() => downloadCSV(rows, filename)}><DownloadSimple size={17} aria-hidden="true" />{children}</button>;
}

export function GeographyToggle({ value, onChange, label = 'Select geography' }) {
  return <div className="segmented" role="group" aria-label={label}>
    {['Statewide', 'BPS'].map(geo => <button key={geo} type="button" aria-pressed={value === geo} className={value === geo ? 'active' : ''} onClick={() => onChange(geo)}>{geo === 'BPS' ? 'Boston Public Schools' : 'Massachusetts sample'}</button>)}
  </div>;
}

function BarTooltip({ active, payload, suffix }) {
  if (!active || !payload?.length) return null;
  const row = payload[0].payload;
  return <div className="chart-tooltip" style={{ background: '#fffdf7', border: '1px solid #d6d6c9', padding: '12px 16px', color: '#172f40' }}>
    <strong>{FULL_GROUPS[row.sesGroup]} · {groupRange(row)}</strong>
    <div>{number(row.value)}{suffix} {row.measureLabel || ''}</div>
    {row.count != null && <small>{row.count} reporting schools</small>}
  </div>;
}

export function GroupBars({ rows, valueKey = 'mean', countKey = 'nUsable', title, subtitle, axisLabel, unit = '%', percentScale = true, showFootnote = true }) {
  const id = useId();
  const [chartRef, chartWidth] = useChartWidth();
  const compact = chartWidth < 470;
  const chartRows = rows.map(row => ({ ...row, name: GROUPS[row.sesGroup], value: row[valueKey], count: row[countKey] }));
  const valid = chartRows.map(row => row.value).filter(Number.isFinite);
  const low = Math.min(0, ...valid);
  const high = Math.max(percentScale ? 100 : 1, ...valid);
  const suffix = unit === '%' ? '%' : unit === 'percentage points' ? ' pp' : '';
  const visibleTitle = title || 'School outcomes by student low-income share';
  const geo = rows[0]?.geography === 'BPS' ? 'Boston Public Schools' : rows[0]?.geography === 'Statewide' ? 'Massachusetts school sample' : '';
  const defaultAxis = valueKey === 'schoolCoveragePct' ? 'Schools with usable FAFSA estimates (%)' : valueKey === 'seniorSchoolCoveragePct' ? 'Seniors enrolled at schools with usable estimates (%)' : `${visibleTitle.replace(/ by low-income group| by group/gi, '')} (${unit === '%' ? '%' : unit})`;
  const missingRows = chartRows.filter(row => !Number.isFinite(row.value));
  return <figure ref={chartRef} className="chart-frame research-group-chart" aria-labelledby={`${id}-title`} aria-describedby={`${id}-description`}>
    <figcaption className="research-chart-heading"><h3 id={`${id}-title`} className="research-chart-title">{visibleTitle}</h3><p className="research-chart-subtitle">{subtitle || `${geo}${geo ? ' · ' : ''}${valueKey === 'mean' ? 'Unweighted school means' : 'Coverage of the eligible sample'}`}</p></figcaption>
    <div className="research-chart-legend" aria-label="Groups by proportion of low-income students">{[1, 2, 3].map(group => <span key={group}><i style={{ background: COLORS[group] }} aria-hidden="true" />{FULL_GROUPS[group]}</span>)}</div>
    <p className="research-category-title">Students classified as low income (%)</p>
    <span id={`${id}-description`} className="sr-only">{chartRows.map(row => `${FULL_GROUPS[row.sesGroup]}, ${groupRange(row)}: ${Number.isFinite(row.value) ? `${number(row.value)}${suffix}` : row.nEligible === 0 ? 'no schools in this group' : 'no usable estimate'}`).join('; ')}. Exact values are in the table below.</span>
    <div aria-hidden="true" className="research-bars-canvas" style={{ width: '100%', height: compact ? 326 : 340 }}>
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartRows} layout="vertical" margin={{ top: 5, right: compact ? 48 : 56, bottom: 10, left: 0 }} barSize={compact ? 30 : 38}>
          <CartesianGrid horizontal={false} stroke="#dcded6" strokeDasharray="2 4" />
          <XAxis type="number" domain={[low < 0 ? Math.floor(low / 10) * 10 : 0, high > 100 || !percentScale ? Math.ceil(high * 1.12) : 100]} tickCount={compact ? 3 : 5} minTickGap={12} axisLine={{ stroke: '#c6cdca' }} tickLine={false} tickMargin={10} tick={{ fill: '#4f6268', fontSize: compact ? 11.5 : 13 }} tickFormatter={v => `${number(v, Math.abs(high - low) < 2 ? 1 : 0)}${suffix}`} />
          <YAxis type="category" dataKey="name" width={compact ? 146 : 165} axisLine={false} tickLine={false} interval={0} tick={<CategoryTick rows={chartRows} compact={compact} valueKey={valueKey} />} />
          {low < 0 && <ReferenceLine x={0} stroke="#183d50" />}
          <Tooltip content={<BarTooltip suffix={suffix} />} cursor={{ fill: '#183d5008' }} />
          <Bar dataKey="value" isAnimationActive={false} radius={[0, 2, 2, 0]}>
            {chartRows.map(row => <Cell key={row.sesGroup} fill={COLORS[row.sesGroup]} />)}
            <LabelList dataKey="value" position="right" formatter={value => Number.isFinite(value) ? `${number(value)}${suffix}` : ''} style={{ fill: '#183d50', fontSize: compact ? 12 : 14, fontWeight: 700 }} />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
    <p className="research-value-axis-title">{axisLabel || defaultAxis}</p>
    {missingRows.length > 0 && <div className="research-missing-note">{missingRows.map(row => <p key={row.sesGroup}><strong>{FULL_GROUPS[row.sesGroup]}:</strong> {row.nEligible === 0 ? 'No schools in this group.' : 'No usable estimate is available.'} This is not a zero outcome.</p>)}</div>}
    <>{showFootnote && <p className="research-chart-footnote">Groups use the same statewide cutoffs. “Higher proportion” means more of a school’s students are classified as low income. N is the number of reporting schools.</p>}</>
  </figure>;
}

export function CoefficientPlot({ rows, title, unitLabel = 'Percentage-point difference' }) {
  const id = useId();
  const [chartRef, chartWidth] = useChartWidth();
  const values = rows.flatMap(row => [row.ciLow, row.ciHigh]).filter(Number.isFinite);
  if (!values.length) return <p className="note">No estimable model is available for this selection.</p>;
  const rawMin = Math.min(0, ...values), rawMax = Math.max(0, ...values);
  const rough = Math.max((rawMax - rawMin) / 5, .1), power = 10 ** Math.floor(Math.log10(rough));
  const step = [1, 2, 5, 10].find(n => n * power >= rough) * power;
  const min = Math.floor(rawMin / step) * step, max = Math.max(min + step, Math.ceil(rawMax / step) * step);
  const width = Math.max(260, chartWidth);
  const x = n => 22 + ((n - min) / (max - min)) * (width - 44);
  const ticks = Array.from({ length: Math.round((max - min) / step) + 1 }, (_, i) => min + step * i);
  return <figure ref={chartRef} className="coefficient-plot research-coefficient-chart" style={{ margin: 0 }} aria-labelledby={id}>
    <figcaption className="research-chart-heading"><h3 id={id} className="research-chart-title">{title || 'Estimated associations and uncertainty'}</h3><p className="research-chart-subtitle">Estimates with nominal 95% confidence intervals</p></figcaption>
    <div className="research-chart-legend research-coefficient-legend"><span><i className="legend-point" aria-hidden="true" />Estimated difference</span><span><i className="legend-interval" aria-hidden="true" />95% confidence interval</span><span><i className="legend-zero" aria-hidden="true" />Zero: no estimated difference</span></div>
    {rows.some(row => row.exploratoryCampusIncome) && <p className="research-chart-footnote">Terracotta points include exploratory campus-income adjustment.</p>}
    {rows.map((row, index) => <div className="coefficient-row" key={`${row.model}-${row.term || index}`} style={{ padding: '14px 0 10px', borderBottom: '1px solid #dcded6' }}>
      <div className="coef-meta" style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8, fontSize: 14 }}><strong>{row.label || row.model}</strong><span>{signed(row.estimate)} <span className="note">[{interval(row)}]</span></span></div>
      <svg viewBox={`0 0 ${width} 48`} style={{ width: '100%', height: 48, display: 'block' }} role="img" aria-label={`${row.label || row.model}: ${signed(row.estimate)}; 95% confidence interval ${interval(row)}; p ${pValue(row.pValue)}`}>
        {ticks.map(tick => <line key={tick} x1={x(tick)} x2={x(tick)} y1={3} y2={39} stroke={Math.abs(tick) < 1e-9 ? '#7c8887' : '#e3e5dd'} strokeDasharray={Math.abs(tick) < 1e-9 ? '4 3' : undefined} />)}
        <line x1={x(row.ciLow)} x2={x(row.ciHigh)} y1={21} y2={21} stroke="#183d50" strokeWidth={2.5} />
        <line x1={x(row.ciLow)} x2={x(row.ciLow)} y1={14} y2={28} stroke="#183d50" strokeWidth={2} />
        <line x1={x(row.ciHigh)} x2={x(row.ciHigh)} y1={14} y2={28} stroke="#183d50" strokeWidth={2} />
        <circle cx={x(row.estimate)} cy={21} r={5} fill={row.exploratoryCampusIncome ? '#B77756' : '#183d50'} stroke="#fffdf7" strokeWidth={1.5} />
      </svg>
    </div>)}
    <svg viewBox={`0 0 ${width} 36`} aria-hidden="true" style={{ width: '100%', height: 36, display: 'block' }}>
      {ticks.map(tick => <text key={tick} x={x(tick)} y={22} textAnchor="middle" fill="#4f6268" fontSize={13}>{number(tick, step < 1 ? 1 : 0)}</text>)}
    </svg>
    <p className="research-value-axis-title">{unitLabel}</p><p className="research-chart-footnote">The dashed vertical line marks zero. An interval crossing zero includes both negative and positive associations.</p>
  </figure>;
}

export function TableDisclosure({ children, label = 'View the underlying data' }) {
  return <details className="table-toggle"><summary>{label}</summary><div className="table-scroll" tabIndex={0}>{children}</div></details>;
}
