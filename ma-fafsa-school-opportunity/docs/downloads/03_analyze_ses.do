/* MA public-school SES and outcomes: first analysis, 5 October 2026.
   Stata 16+. Run the WHOLE file after the successful 02 enrollment merge.
   This file was statically reviewed; its first Stata runtime check is your log.
   Main sample: 407 original schools with positive 2024-25 senior enrollment.
   Outcomes measure different school populations; estimates are associations.
   Two additional senior-enrolling schools remain outside this merged sample.
   Original input files and the 02 merged dataset are never overwritten.
*/
version 16.0
clear all
set more off
set varabbrev off
set linesize 160
global MA_PROJECT "/Users/benw/Desktop/useful/MA_SES_Project"
global MA03 "$MA_PROJECT/output/03_analysis"
cd "$MA_PROJECT"
capture mkdir "$MA03"
capture mkdir "$MA03/figures"
capture mkdir "$MA03/estimates"
capture log close _all
log using "$MA03/03_analysis.log", text replace

* 1. Use the successfully checked enrollment merge, not the old cohort proxy.
confirm file "$MA_PROJECT/output/02_enrollment_merged.dta"
use "$MA_PROJECT/output/02_enrollment_merged.dta", clear
assert _N==415
isid school_code
assert strlen(school_code)==8 & regexm(school_code,"^[0-9]+$")
assert ma_senior_scope==1 if grade12_enrollment>0 & !missing(grade12_enrollment)
quietly count if ma_senior_scope==1
assert r(N)==407
quietly count if !missing(ma_fafsa_senior)
assert r(N)==356
assert inrange(ma_fafsa_senior,0,100) if !missing(ma_fafsa_senior)
assert missing(ma_fafsa_senior) if ma_fafsa_over100==1 | ma_fafsa_multirow==1
assert src_cycle=="2025-26" & src_cutoff=="2025-05-31"
gen byte ma_primary=ma_senior_scope==1
gen byte ma_bps=strtrim(district_name)=="Boston"
label var ma_primary "Current merged sample with positive 2024-25 senior enrollment"
label var ma_bps "Boston Public Schools district; separate charter districts excluded"
gen byte ma_bps_exam=inlist(school_code,"00350545","00350560","00350575")
label var ma_bps_exam "Boston Latin School, Boston Latin Academy or O'Bryant"
assert ma_bps==1 if ma_bps_exam==1
quietly count if ma_primary==1 & ma_bps==1
assert r(N)==31
quietly count if ma_bps_exam==1
assert r(N)==3

* Primary outcomes. Missing/suppressed values remain missing.
gen double ma_fafsa=ma_fafsa_senior
label var ma_fafsa "Estimated FAFSA completions / enrolled seniors (%)"
label var college_attend_pct "College attendance among 2024-25 graduates (%)"
label var grad_pct "2025 four-year graduation rate (%)"
label var masscore_completed_pct "2024-25 MassCore completion among graduates (%)"
label var ap_perf_pct_score_3_5 "2024-25 AP exams scoring 3-5 (%)"
label var att_chronic_abs_10pct "2024-25 whole-school chronic absence (%)"
local outcomes ma_fafsa college_attend_pct grad_pct masscore_completed_pct ///
    ap_perf_pct_score_3_5 att_chronic_abs_10pct
local keys F C G M A H
foreach y of local outcomes {
    assert inrange(`y',0,100) if !missing(`y')
}

* 2. Fixed statewide SES groups. Higher group number = lower low-income share.
assert !missing(sel_low_income_pct,sel_el_pct,sel_swd_pct) if ma_primary==1
assert enrollment_total>0 & enrollment_9_12>0 ///
    & !missing(enrollment_total,enrollment_9_12) if ma_primary==1
gen double ma_low10=sel_low_income_pct/10
label var ma_low10 "Low-income share, per 10 percentage points"
gen double ma_neg_low=-sel_low_income_pct
xtile ma_ses3=ma_neg_low if ma_primary==1, nq(3)
xtile ma_ses4=ma_neg_low if ma_primary==1, nq(4)
label define ma03_ses3 1 "Higher low-income share" 2 "Middle low-income share" ///
    3 "Lower low-income share"
label define ma03_ses4 1 "Highest low-income share" 2 "Upper-middle share" ///
    3 "Lower-middle share" 4 "Lowest low-income share"
label values ma_ses3 ma03_ses3
label values ma_ses4 ma03_ses4
label var ma_ses3 "Three groups, fixed across the 407 eligible statewide records"
label var ma_ses4 "Four groups, fixed across the 407 eligible statewide records"
assert !missing(ma_ses3,ma_ses4) if ma_primary==1
assert missing(ma_ses3) & missing(ma_ses4) if ma_primary==0
tab ma_ses3 if ma_primary==1, missing
tab ma_ses3 if ma_bps==1 & ma_primary==1, missing
tabstat sel_low_income_pct if ma_primary==1, by(ma_ses3) stat(n min max mean)

* Campus income is exploratory while ACS vintage/geocoding are unresolved.
assert acs_median_hh_income>0 if !missing(acs_median_hh_income)
gen double ma_log2inc=ln(acs_median_hh_income)/ln(2)
gen double ma_income10k=acs_median_hh_income/10000
gen byte ma_income_top=acs_median_hh_income==250001 if !missing(acs_median_hh_income)
gen byte ma_income_sample=ma_primary==1 & !missing(ma_log2inc,sel_low_income_pct)
egen double ma_zlow=std(sel_low_income_pct) if ma_income_sample==1
egen double ma_zinc=std(ma_log2inc) if ma_income_sample==1
gen double ma_composite=(-ma_zlow+ma_zinc)/2 if ma_income_sample==1
xtile ma_combined3=ma_composite if ma_income_sample==1, nq(3)
xtile ma_combined4=ma_composite if ma_income_sample==1, nq(4)
label var ma_log2inc "Campus-tract income, per doubling; exploratory ACS context"
label var ma_composite "Exploratory SES index: equal weights on -z(low income) and z(log income)"
label var ma_combined3 "Three exploratory combined SES groups; 1 lower, 3 higher"
label var ma_combined4 "Four exploratory combined SES groups; 1 lower, 4 higher"

* School-size controls: grades 9-12 for high-school outcomes; total for absence.
gen double ma_ln912=ln(enrollment_9_12) if enrollment_9_12>0 & !missing(enrollment_9_12)
gen double ma_lntotal=ln(enrollment_total) if enrollment_total>0 & !missing(enrollment_total)
label var ma_ln912 "Log 2024-25 enrollment in grades 9-12"
label var ma_lntotal "Log 2024-25 total school enrollment, all source grades"
gen byte ma_type=4
replace ma_type=1 if school_type=="Public Secondary"
replace ma_type=2 if school_type=="Charter"
replace ma_type=3 if school_type=="Public Voc/Tech/Ag Reg'l HS"
label define ma03_type 1 "Public secondary" 2 "Charter" 3 "Vocational/technical" 4 "Other reported type"
label values ma_type ma03_type
label var ma_type "Four categories based on the supplied school-type field"
egen long ma_district=group(district_name) if strtrim(district_name)!=""
assert !missing(ma_district) if ma_primary==1

* 3. Descriptive tables. Means give each school equal weight; N is shown per outcome.
tempname D
postfile `D' str12 geography str20 grouping byte ses_group str32 outcome ///
    long(n_group n_available) double(mean sd minimum maximum) ///
    using "$MA03/03_group_descriptives.dta", replace
local describe_vars `outcomes' sel_low_income_pct acs_median_hh_income ///
    grade12_enrollment enrollment_9_12 ap_part_tests_takers
foreach grouping in ma_ses3 ma_ses4 ma_combined3 ma_combined4 {
    quietly levelsof `grouping' if ma_primary==1, local(levels)
    foreach geo in Statewide BPS {
        foreach g of local levels {
            quietly count if ma_primary==1 & `grouping'==`g' ///
                & ("`geo'"=="Statewide" | ma_bps==1)
            local ng=r(N)
            foreach y of local describe_vars {
                quietly summarize `y' if ma_primary==1 & `grouping'==`g' ///
                    & ("`geo'"=="Statewide" | ma_bps==1)
                post `D' ("`geo'") ("`grouping'") (`g') ("`y'") ///
                    (`ng') (r(N)) (r(mean)) (r(sd)) (r(min)) (r(max))
            }
        }
    }
}
postclose `D'
preserve
use "$MA03/03_group_descriptives.dta", clear
gen long n_missing=n_group-n_available
export delimited using "$MA03/03_group_descriptives.csv", replace
restore

preserve
keep if ma_primary==1
collapse (count) n_schools=sel_low_income_pct ///
    (min) low_income_min=sel_low_income_pct ///
    (max) low_income_max=sel_low_income_pct ///
    (mean) low_income_mean=sel_low_income_pct, by(ma_ses3)
decode ma_ses3, gen(ses_label)
export delimited using "$MA03/03_ses3_ranges.csv", nolabel replace
restore
preserve
keep if ma_primary==1
collapse (count) n_schools=sel_low_income_pct ///
    (min) low_income_min=sel_low_income_pct ///
    (max) low_income_max=sel_low_income_pct, by(ma_ses4)
decode ma_ses4, gen(ses_label)
export delimited using "$MA03/03_ses4_ranges.csv", nolabel replace
restore

* 4. Pairwise correlations. Supplementary MCAS/SAT are not Class-of-2025 panels.
local corrvars `outcomes' sel_low_income_pct ma_log2inc acs_bachelors_pct ///
    acs_poverty_rate ap_part_tests_takers mcas_math_avg_score mcas_ela_avg_score ///
    mcas_sci_avg_score sat_math sat_reading_writing
pwcorr `outcomes' sel_low_income_pct ma_log2inc if ma_primary==1, sig obs
pwcorr ma_fafsa mcas_math_avg_score mcas_ela_avg_score mcas_sci_avg_score ///
    sat_math sat_reading_writing acs_bachelors_pct if ma_primary==1, sig obs
tempname C
postfile `C' str32(x y) long n double(correlation p) ///
    using "$MA03/03_correlations.dta", replace
local k: word count `corrvars'
forvalues i=1/`k' {
    local next=`i'+1
    if `next'<=`k' {
        forvalues j=`next'/`k' {
            local x: word `i' of `corrvars'
            local y: word `j' of `corrvars'
            quietly count if ma_primary==1 & !missing(`x',`y')
            local n=r(N)
            local rho=.
            local p=.
            if `n'>2 {
                capture quietly correlate `x' `y' if ma_primary==1
                if _rc==0 {
                    matrix corrmat=r(C)
                    local rho=corrmat[1,2]
                    if !missing(`rho') & abs(`rho')<1 ///
                        local p=2*ttail(`n'-2,abs(`rho')*sqrt((`n'-2)/(1-(`rho')^2)))
                    if !missing(`rho') & abs(`rho')==1 local p=0
                }
            }
            post `C' ("`x'") ("`y'") (`n') (`rho') (`p')
        }
    }
}
postclose `C'
preserve
use "$MA03/03_correlations.dta", clear
gen str120 inference_note="Exploratory Pearson p; school independence assumed; not adjusted for district clustering or multiple tests"
export delimited using "$MA03/03_correlations.csv", replace
restore

* 5. Helper exports coefficients, confidence intervals and actual model samples.
capture program drop ma03_fit
program define ma03_fit
    syntax varlist(min=2 numeric fv) [if] [in], ID(name) OUTCOME(name) ///
        HANDLE(name) [CLUSTER(varname)]
    local vce "robust"
    if "`cluster'"=="" {
        regress `varlist' `if' `in', vce(robust)
    }
    else {
        regress `varlist' `if' `in', vce(cluster `cluster')
        local vce "district clustered"
    }
    estimates store `id'
    estimates save "$MA03/estimates/`id'.ster", replace
    tempname B V
    matrix `B'=e(b)
    matrix `V'=e(V)
    local terms: colnames `B'
    local n=e(N)
    local r2=e(r2)
    local df=e(df_r)
    local nc=.
    if "`cluster'"!="" local nc=e(N_clust)
    local crit=invttail(`df',.025)
    local columns=colsof(`B')
    forvalues j=1/`columns' {
        local term: word `j' of `terms'
        local b=`B'[1,`j']
        local se=sqrt(`V'[`j',`j'])
        local p=.
        local lb=.
        local ub=.
        if `se'>0 & !missing(`se') {
            local p=2*ttail(`df',abs(`b'/`se'))
            local lb=`b'-`crit'*`se'
            local ub=`b'+`crit'*`se'
        }
        post `handle' ("`id'") ("`outcome'") ("`term'") ("`vce'") ///
            (`b') (`se') (`p') (`lb') (`ub') (`n') (`r2') (`df') (`nc')
    }
end
tempname R
postfile `R' str24 model str32 outcome str48 term str20 vce ///
    double(b se p ci_low ci_high n r2 df n_clusters) ///
    using "$MA03/03_regression_coefficients.dta", replace

* Main: broad unadjusted; SAME-SAMPLE unadjusted and adjusted low-income models.
* District clustering allows correlated errors among schools in the same district.
local j=0
foreach y of local outcomes {
    local j=`j'+1
    local key: word `j' of `keys'
    local size ma_ln912
    if "`key'"=="H" local size ma_lntotal
    local controls `size' i.ma_type sel_el_pct sel_swd_pct
    gen byte ma_s_`key'=ma_primary==1 & !missing(`y',ma_low10,ma_district)
    gen byte ma_c_`key'=ma_s_`key'==1 ///
        & !missing(`size',ma_type,sel_el_pct,sel_swd_pct)
    ma03_fit `y' ma_low10 if ma_s_`key'==1, ///
        id(M0_`key') outcome(`y') handle(`R') cluster(ma_district)
    ma03_fit `y' ma_low10 if ma_c_`key'==1, ///
        id(M1_`key') outcome(`y') handle(`R') cluster(ma_district)
    ma03_fit `y' ma_low10 `controls' if ma_c_`key'==1, ///
        id(M2_`key') outcome(`y') handle(`R') cluster(ma_district)
    ma03_fit `y' ib1.ma_ses3 if ma_s_`key'==1, ///
        id(G3_`key') outcome(`y') handle(`R') cluster(ma_district)
    ma03_fit `y' ib1.ma_ses4 if ma_s_`key'==1, ///
        id(G4_`key') outcome(`y') handle(`R') cluster(ma_district)

    * Exploratory income models all use the SAME income/control-complete sample.
    gen byte ma_i_`key'=ma_c_`key'==1 & !missing(ma_log2inc)
    ma03_fit `y' ma_log2inc if ma_i_`key'==1, ///
        id(I1_`key') outcome(`y') handle(`R') cluster(ma_district)
    ma03_fit `y' ma_low10 ma_log2inc if ma_i_`key'==1, ///
        id(I2_`key') outcome(`y') handle(`R') cluster(ma_district)
    ma03_fit `y' ma_low10 ma_log2inc `controls' if ma_i_`key'==1, ///
        id(I3_`key') outcome(`y') handle(`R') cluster(ma_district)
}

* 6. Targeted sensitivities for the primary FAFSA outcome.
ma03_fit ma_fafsa ma_low10 ma_lntotal i.ma_type sel_el_pct sel_swd_pct ///
    if ma_c_F==1, id(S_total) outcome(ma_fafsa) handle(`R') cluster(ma_district)
ma03_fit ma_fafsa ma_low10 ma_ln912 sel_el_pct sel_swd_pct ///
    if ma_c_F==1 & school_type=="Public Secondary", ///
    id(S_secondary) outcome(ma_fafsa) handle(`R') cluster(ma_district)
ma03_fit ma_fafsa ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct ///
    if ma_i_F==1 & ma_income_top==0, ///
    id(S_no_top) outcome(ma_fafsa) handle(`R') cluster(ma_district)
ma03_fit ma_fafsa ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct ///
    if ma_i_F==1 & acs_location_count==1, ///
    id(S_onecampus) outcome(ma_fafsa) handle(`R') cluster(ma_district)
ma03_fit ma_fafsa_original_archive ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct ///
    if ma_c_F==1, id(S_archive) outcome(ma_fafsa_original_archive) ///
    handle(`R') cluster(ma_district)

* BPS is one district: use robust SE for simple exploratory models, not district clustering.
ma03_fit ma_fafsa ma_low10 if ma_primary==1 & ma_bps==1, ///
    id(BPS_F) outcome(ma_fafsa) handle(`R')
ma03_fit college_attend_pct ma_low10 if ma_primary==1 & ma_bps==1, ///
    id(BPS_C) outcome(college_attend_pct) handle(`R')
ma03_fit ma_fafsa ma_low10 if ma_primary==1 & ma_bps==1 & ma_bps_exam==0, ///
    id(BPS_no_exam) outcome(ma_fafsa) handle(`R')

* Exploratory FAFSA/college association. This does not estimate an application intervention.
gen byte ma_fc=ma_primary==1 & !missing(ma_fafsa,college_attend_pct,ma_low10, ///
    ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
ma03_fit college_attend_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct ///
    if ma_fc==1, id(C_base) outcome(college_attend_pct) handle(`R') cluster(ma_district)
ma03_fit college_attend_pct ma_fafsa ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct ///
    if ma_fc==1, id(C_plus_F) outcome(college_attend_pct) handle(`R') cluster(ma_district)

* Documented historical specifications: reruns on the ORIGINAL 415-record universe.
* Use original graduation-cohort proxy, never substitute these for primary senior estimates.
ma03_fit ma_fafsa_original_proxy sel_low_income_pct, ///
    id(H1) outcome(ma_fafsa_original_proxy) handle(`R')
ma03_fit college_attend_pct ma_fafsa_original_proxy, ///
    id(H2) outcome(college_attend_pct) handle(`R')
ma03_fit college_attend_pct sel_low_income_pct, ///
    id(H3) outcome(college_attend_pct) handle(`R')
ma03_fit ma_fafsa_original_proxy att_chronic_abs_10pct, ///
    id(H4) outcome(ma_fafsa_original_proxy) handle(`R')
ma03_fit college_attend_pct acs_bachelors_pct, ///
    id(H5) outcome(college_attend_pct) handle(`R')
ma03_fit ma_fafsa_original_proxy ma_income10k, ///
    id(H6) outcome(ma_fafsa_original_proxy) handle(`R')
postclose `R'

* 7. Compact model tables and multiplicity check for the six MAIN adjusted SES tests.
preserve
use "$MA03/03_regression_coefficients.dta", clear
gen byte zero_se=se==0 if !missing(se)
export delimited using "$MA03/03_regression_coefficients.csv", replace
keep if term=="_cons"
keep model outcome vce n r2 df n_clusters
export delimited using "$MA03/03_model_samples.csv", replace
use "$MA03/03_regression_coefficients.dta", clear
keep if substr(model,1,3)=="M2_" & term=="ma_low10"
assert _N==6
assert !missing(p,b,se,ci_low,ci_high)
sort p outcome
gen byte test_order=_n
gen double p_holm=min(1,(_N-_n+1)*p)
replace p_holm=max(p_holm,p_holm[_n-1]) if _n>1
label var p_holm "Holm p across six main adjusted low-income tests; secondary check"
export delimited using "$MA03/03_main_low_income_results.csv", replace
list outcome b se ci_low ci_high n p p_holm, noobs
restore

* 8. Draft website figures. Fixed statewide groups also used for BPS.
set scheme s2color
foreach y of local outcomes {
    local title: variable label `y'
    graph bar (mean) `y' if ma_primary==1, ///
        over(ma_ses3, label(labsize(small))) ///
        bar(1,color(navy)) ytitle("Percent") ///
        title("`title'",size(medsmall)) ///
        note("Unweighted school means. Available N by group: 03_group_descriptives.csv." ///
             "Current merged sample with seniors; outcome populations differ.",size(vsmall)) ///
        graphregion(color(white)) name(ma03_bar, replace)
    graph export "$MA03/figures/`y'_ses3.png", width(1800) replace
    graph export "$MA03/figures/`y'_ses3.svg", replace
    graph save "$MA03/figures/`y'_ses3.gph", replace
}
foreach y in ma_fafsa college_attend_pct {
    local title: variable label `y'
    graph bar (mean) `y' if ma_primary==1 & ma_bps==1, ///
        over(ma_ses3,label(labsize(small))) ///
        bar(1,color(navy)) ytitle("Percent") ///
        title("BPS: `title'",size(medsmall)) ///
        note("Statewide SES cutoffs; BPS district only. Small groups; see available N in CSV.",size(vsmall)) ///
        graphregion(color(white)) name(ma03_bps,replace)
    graph export "$MA03/figures/bps_`y'_ses3.png",width(1800) replace
    graph export "$MA03/figures/bps_`y'_ses3.svg",replace
}
twoway (scatter ma_fafsa sel_low_income_pct if ma_primary==1 & ma_bps==0, ///
    mcolor(gs11) msymbol(oh) msize(small)) ///
    (scatter ma_fafsa sel_low_income_pct if ma_primary==1 & ma_bps==1, ///
    mcolor(navy) msymbol(O) msize(small)), ///
    legend(order(1 "Other districts" 2 "BPS district")) ///
    xtitle("Students identified as low income (%)") ///
    ytitle("Estimated FAFSA completions / enrolled seniors (%)") ///
    title("Boston Public Schools in the statewide sample") ///
    note("May 31, 2025 snapshot; screened estimated ratios; school-level associations.",size(vsmall)) ///
    graphregion(color(white)) name(ma03_scatter,replace)
graph export "$MA03/figures/boston_fafsa_scatter.png",width(1800) replace
graph export "$MA03/figures/boston_fafsa_scatter.svg",replace

* Later pathways counts are kept separate; not ordinary senior enrollment.
preserve
keep if ma_primary==1
keep school_code school_name district_name path_grade_9 path_grade_10 path_grade_11 ///
    path_grade_12 path_total path_pct_all_students
gen str7 source_year="2025-26"
export delimited using "$MA03/03_pathways_2025_26_context.csv",replace
restore

* 9. Save all records with scope flags, groups, model samples and original variables.
gen str150 ma_analysis_status="DRAFT school-level associations; sample coverage, FAFSA population, ACS provenance, MCAS filters and college follow-up remain review items"
sort school_code
isid school_code
assert _N==415
save "$MA03/03_analysis_ready.dta", replace
preserve
keep school_code school_name district_name school_type grades ma_primary ma_bps ///
    ma_bps_exam sel_low_income_pct acs_median_hh_income acs_location_count ///
    grade12_enrollment enrollment_total enrollment_9_12 ma_ses3 ma_ses4 ///
    ma_composite ma_combined3 ma_combined4 `outcomes' ///
    ma_fafsa_original_proxy ma_fafsa_original_archive ma_fafsa_senior_raw ///
    fafsa_suppressed fafsa_review_flag ma_fafsa_over100 ma_fafsa_multirow ///
    ma_fafsa_senior_usable ma_fafsa_basis ma_source_review ma_analysis_status
export delimited using "$MA03/03_school_data.csv",nolabel replace
restore
display as result "ANALYSIS COMPLETED: SES groups, descriptive tables, correlations, models and figures saved."
display as text "Outputs: output/03_analysis/. Original and 02 input datasets were not overwritten."
display as text "Send 03_analysis.log, 03_main_low_income_results.csv and 03_group_descriptives.csv for review."
display as text "Coefficients are associations, not causal effects. Source definitions remain visible."
log close
* END OF 03 ANALYSIS
