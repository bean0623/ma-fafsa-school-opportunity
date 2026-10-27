/* Additional outcomes and transparent FAFSA comparisons, 7 October 2026.
   Stata 16+, built-in commands. Run the WHOLE file after stages 03-05.
   First actual Stata execution will be on your Mac; independent numerical
   reference values are checked automatically. Original files are preserved.
*/
version 16.0
clear all
set more off
set varabbrev off
set linesize 160
global MA_PROJECT "/Users/benw/Desktop/useful/MA_SES_Project"
global MA06 "$MA_PROJECT/output/06_additional_models"
cd "$MA_PROJECT"
capture mkdir "$MA06"
capture mkdir "$MA06/estimates"
capture log close _all
log using "$MA06/06_additional_models.log", text replace
confirm file "$MA_PROJECT/output/03_analysis/03_analysis_ready.dta"
confirm file "$MA_PROJECT/data/06_expected_ses_coefficients.csv"
confirm file "$MA_PROJECT/data/06_outcome_catalogue.csv"
use "$MA_PROJECT/output/03_analysis/03_analysis_ready.dta", clear
assert _N==415
isid school_code
quietly count if ma_primary==1
assert r(N)==407
quietly count if !missing(ma_fafsa)
assert r(N)==356
assert inrange(ma_fafsa,0,100) if !missing(ma_fafsa)
assert src_cycle=="2025-26" & src_cutoff=="2025-05-31"
assert !missing(ma_ses3,ma_ses4,ma_low10,ma_ln912,ma_lntotal,ma_type,sel_el_pct,sel_swd_pct,ma_district) if ma_primary==1

* These flags describe source restrictions, not data-dependent exclusions.
gen byte ma06_plan_aligned=plan_total_count==college_graduates_num ///
    & plan_total_count>0 & !missing(plan_total_count,college_graduates_num)
gen byte ma06_path_gt100=path_pct_all_students>100 & !missing(path_pct_all_students)
gen double ma06_plan_college=plan_priv_4yr+plan_pub_4yr+plan_priv_2yr+plan_pub_2yr
gen double ma06_plan4=plan_priv_4yr+plan_pub_4yr
gen double ma06_college4_grad=college_attend_pct*(college_priv_4yr_pct+college_pub_4yr_pct)/100
gen double ma06_plan_gap=ma06_plan_college-college_attend_pct if ma06_plan_aligned==1
label var ma06_plan_gap "Planned minus observed college attendance, matched school graduate counts"
label var ma06_college4_grad "Estimated four-year college attendance among graduates; rounded source rates"
local planparts plan_priv_4yr plan_pub_4yr plan_priv_2yr plan_pub_2yr ///
    plan_other_postsec plan_apprenticeship plan_work plan_military plan_other plan_unknown
local sectors college_priv_2yr_pct college_priv_4yr_pct college_pub_2yr_pct college_pub_4yr_pct
egen double ma06_plan_sum=rowtotal(`planparts')
egen byte ma06_plan_miss=rowmiss(`planparts')
egen double ma06_sector_sum=rowtotal(`sectors')
egen byte ma06_sector_miss=rowmiss(`sectors')
assert inrange(ma06_plan_sum,99.4,100.6) if ma06_plan_miss==0
assert inrange(ma06_sector_sum,0,100.3) if ma06_sector_miss==0
foreach y of local planparts {
    assert inrange(`y',0,100) if !missing(`y')
}
foreach y of local sectors {
    assert inrange(`y',0,100) if !missing(`y')
}
assert inrange(grad_dropout_pct,0,100) if !missing(grad_dropout_pct)
assert inrange(att_chronic_abs_20pct,0,100) if !missing(att_chronic_abs_20pct)
assert inrange(ma06_plan_college,0,100.3) if !missing(ma06_plan_college)
assert inrange(ma06_plan4,0,100.2) if !missing(ma06_plan4)
assert ap_part_tests_takers>=0 & ap_part_tests_takers==floor(ap_part_tests_takers) if !missing(ap_part_tests_takers)
assert path_total>=0 & path_total==floor(path_total) if !missing(path_total)

* Export source mismatches and published pathways percentages above 100.
preserve
keep if ma_primary==1 & ma06_sector_miss==0 & college_attend_num>0 ///
    & !missing(college_attend_num) & abs(ma06_sector_sum-100)>.3
keep school_code school_name college_attend_num `sectors' ma06_sector_sum
export delimited using "$MA06/06_college_sector_review.csv", replace
restore
preserve
keep if ma_primary==1 & !missing(plan_total_count,college_graduates_num) & ma06_plan_aligned==0
keep school_code school_name plan_total_count college_graduates_num
export delimited using "$MA06/06_plan_denominator_review.csv", replace
restore
preserve
keep if ma_primary==1 & ma06_path_gt100==1
keep school_code school_name path_total path_pct_all_students
export delimited using "$MA06/06_pathways_over100.csv", replace
restore

* Helper exports every coefficient. Expected small/constant samples are logged.
capture program drop ma06_fit
program define ma06_fit
    syntax varlist(min=2 numeric fv), ID(name) OUTCOME(name) SPEC(string) ///
        GEO(string) FAMILY(string) SAMPLE(varname) HANDLE(name) STATUS(name) [CLUSTER(varname)]
    quietly count if `sample'==1
    local n=r(N)
    local nc=.
    if "`cluster'"!="" {
        quietly levelsof `cluster' if `sample'==1, local(clusters)
        local nc: word count `clusters'
    }
    local reason "fitted"
    if `n'<15 local reason "skipped: fewer than 15 schools"
    if "`cluster'"!="" & `nc'<10 local reason "skipped: fewer than 10 districts"
    quietly summarize `outcome' if `sample'==1
    if r(N)>1 & r(sd)==0 local reason "skipped: constant outcome"
    quietly summarize ma_low10 if `sample'==1
    if r(N)>1 & r(sd)==0 local reason "skipped: constant low-income share"
    post `status' ("`id'") ("`outcome'") ("`spec'") ("`geo'") ("`family'") (`n') (`nc') ("`reason'")
    if "`reason'"!="fitted" {
        display as text "`id': `reason'"
        exit
    }
    local vce "robust"
    if "`cluster'"=="" {
        regress `varlist' if `sample'==1, vce(robust)
    }
    else {
        regress `varlist' if `sample'==1, vce(cluster `cluster')
        local vce "district clustered"
    }
    assert e(N)==`n'
    estimates store `id'
    estimates save "$MA06/estimates/`id'.ster", replace
    tempname B V
    matrix `B'=e(b)
    matrix `V'=e(V)
    local terms: colnames `B'
    local df=e(df_r)
    local r2=e(r2)
    local crit=invttail(`df',.025)
    local k=colsof(`B')
    forvalues j=1/`k' {
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
        post `handle' ("`id'") ("`outcome'") ("`spec'") ("`geo'") ("`family'") ///
            ("`vce'") ("`term'") (`b') (`se') (`lb') (`ub') (`p') (`n') (`nc') (`df') (`r2')
    }
end
tempname R S D F
postfile `R' str20 model str32 outcome str16 specification str12 geography str20 family ///
    str20 vce str32 term double(b se ci_low ci_high p) long n n_clusters double(df r2) ///
    using "$MA06/06_regression_coefficients.dta", replace
postfile `S' str20 model str32 outcome str16 specification str12 geography str20 family ///
    long n n_clusters str60 status using "$MA06/06_model_status.dta", replace
postfile `D' str32 outcome str12 geography byte ses_group ///
    long(n_eligible n_available n_common) double(mean sd minimum maximum) ///
    using "$MA06/06_outcomes_by_ses.dta", replace
postfile `F' str20 model str50 contrast double(b se ci_low ci_high p) long n ///
    using "$MA06/06_fafsa_contrasts.dta", replace

* 1. Private two-year college destination. Class of 2025; March 2026; share of college attendees, not all graduates.
gen byte ma06_s01=ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) ///
    & !missing(college_priv_2yr_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b01=ma06_s01==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s01==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize college_priv_2yr_pct if ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("college_priv_2yr_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit college_priv_2yr_pct ma_low10, id(U_01) outcome(college_priv_2yr_pct) spec(unadjusted) geo(Statewide) family(destinations) sample(ma06_s01) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_priv_2yr_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_01) outcome(college_priv_2yr_pct) spec(adjusted) geo(Statewide) family(destinations) sample(ma06_s01) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_priv_2yr_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_01) outcome(college_priv_2yr_pct) spec(income_adj) geo(Statewide) family(destinations) sample(ma06_s01) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_priv_2yr_pct ma_low10, id(B_01) outcome(college_priv_2yr_pct) spec(BPS_simple) geo(BPS) family(destinations) sample(ma06_b01) handle(`R') status(`S')
ma06_fit college_priv_2yr_pct ma_low10 ma_log2inc, id(BI_01) outcome(college_priv_2yr_pct) spec(BPS_income) geo(BPS) family(destinations) sample(ma06_b01) handle(`R') status(`S')

* 2. Private four-year college destination. Class of 2025; March 2026; share of college attendees, not all graduates.
gen byte ma06_s02=ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) ///
    & !missing(college_priv_4yr_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b02=ma06_s02==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s02==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize college_priv_4yr_pct if ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("college_priv_4yr_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit college_priv_4yr_pct ma_low10, id(U_02) outcome(college_priv_4yr_pct) spec(unadjusted) geo(Statewide) family(destinations) sample(ma06_s02) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_priv_4yr_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_02) outcome(college_priv_4yr_pct) spec(adjusted) geo(Statewide) family(destinations) sample(ma06_s02) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_priv_4yr_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_02) outcome(college_priv_4yr_pct) spec(income_adj) geo(Statewide) family(destinations) sample(ma06_s02) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_priv_4yr_pct ma_low10, id(B_02) outcome(college_priv_4yr_pct) spec(BPS_simple) geo(BPS) family(destinations) sample(ma06_b02) handle(`R') status(`S')
ma06_fit college_priv_4yr_pct ma_low10 ma_log2inc, id(BI_02) outcome(college_priv_4yr_pct) spec(BPS_income) geo(BPS) family(destinations) sample(ma06_b02) handle(`R') status(`S')

* 3. Public two-year college destination. Class of 2025; March 2026; share of college attendees, not all graduates.
gen byte ma06_s03=ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) ///
    & !missing(college_pub_2yr_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b03=ma06_s03==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s03==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize college_pub_2yr_pct if ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("college_pub_2yr_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit college_pub_2yr_pct ma_low10, id(U_03) outcome(college_pub_2yr_pct) spec(unadjusted) geo(Statewide) family(destinations) sample(ma06_s03) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_pub_2yr_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_03) outcome(college_pub_2yr_pct) spec(adjusted) geo(Statewide) family(destinations) sample(ma06_s03) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_pub_2yr_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_03) outcome(college_pub_2yr_pct) spec(income_adj) geo(Statewide) family(destinations) sample(ma06_s03) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_pub_2yr_pct ma_low10, id(B_03) outcome(college_pub_2yr_pct) spec(BPS_simple) geo(BPS) family(destinations) sample(ma06_b03) handle(`R') status(`S')
ma06_fit college_pub_2yr_pct ma_low10 ma_log2inc, id(BI_03) outcome(college_pub_2yr_pct) spec(BPS_income) geo(BPS) family(destinations) sample(ma06_b03) handle(`R') status(`S')

* 4. Public four-year college destination. Class of 2025; March 2026; share of college attendees, not all graduates.
gen byte ma06_s04=ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) ///
    & !missing(college_pub_4yr_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b04=ma06_s04==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s04==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize college_pub_4yr_pct if ma_primary==1 & (college_attend_num>0 & !missing(college_attend_num)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("college_pub_4yr_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit college_pub_4yr_pct ma_low10, id(U_04) outcome(college_pub_4yr_pct) spec(unadjusted) geo(Statewide) family(destinations) sample(ma06_s04) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_pub_4yr_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_04) outcome(college_pub_4yr_pct) spec(adjusted) geo(Statewide) family(destinations) sample(ma06_s04) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_pub_4yr_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_04) outcome(college_pub_4yr_pct) spec(income_adj) geo(Statewide) family(destinations) sample(ma06_s04) handle(`R') status(`S') cluster(ma_district)
ma06_fit college_pub_4yr_pct ma_low10, id(B_04) outcome(college_pub_4yr_pct) spec(BPS_simple) geo(BPS) family(destinations) sample(ma06_b04) handle(`R') status(`S')
ma06_fit college_pub_4yr_pct ma_low10 ma_log2inc, id(BI_04) outcome(college_pub_4yr_pct) spec(BPS_income) geo(BPS) family(destinations) sample(ma06_b04) handle(`R') status(`S')

* 5. Estimated four-year college attendance among graduates. Class of 2025; March 2026; derived from rounded attendance and destination percentages.
gen byte ma06_s05=ma_primary==1 & (1) ///
    & !missing(ma06_college4_grad,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b05=ma06_s05==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s05==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize ma06_college4_grad if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("ma06_college4_grad") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit ma06_college4_grad ma_low10, id(U_05) outcome(ma06_college4_grad) spec(unadjusted) geo(Statewide) family(destinations) sample(ma06_s05) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_college4_grad ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_05) outcome(ma06_college4_grad) spec(adjusted) geo(Statewide) family(destinations) sample(ma06_s05) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_college4_grad ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_05) outcome(ma06_college4_grad) spec(income_adj) geo(Statewide) family(destinations) sample(ma06_s05) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_college4_grad ma_low10, id(B_05) outcome(ma06_college4_grad) spec(BPS_simple) geo(BPS) family(destinations) sample(ma06_b05) handle(`R') status(`S')
ma06_fit ma06_college4_grad ma_low10 ma_log2inc, id(BI_05) outcome(ma06_college4_grad) spec(BPS_income) geo(BPS) family(destinations) sample(ma06_b05) handle(`R') status(`S')

* 6. Plan: private four-year college. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s06=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_priv_4yr,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b06=ma06_s06==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s06==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_priv_4yr if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_priv_4yr") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_priv_4yr ma_low10, id(U_06) outcome(plan_priv_4yr) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s06) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_priv_4yr ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_06) outcome(plan_priv_4yr) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s06) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_priv_4yr ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_06) outcome(plan_priv_4yr) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s06) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_priv_4yr ma_low10, id(B_06) outcome(plan_priv_4yr) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b06) handle(`R') status(`S')
ma06_fit plan_priv_4yr ma_low10 ma_log2inc, id(BI_06) outcome(plan_priv_4yr) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b06) handle(`R') status(`S')

* 7. Plan: public four-year college. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s07=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_pub_4yr,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b07=ma06_s07==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s07==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_pub_4yr if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_pub_4yr") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_pub_4yr ma_low10, id(U_07) outcome(plan_pub_4yr) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s07) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_pub_4yr ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_07) outcome(plan_pub_4yr) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s07) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_pub_4yr ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_07) outcome(plan_pub_4yr) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s07) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_pub_4yr ma_low10, id(B_07) outcome(plan_pub_4yr) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b07) handle(`R') status(`S')
ma06_fit plan_pub_4yr ma_low10 ma_log2inc, id(BI_07) outcome(plan_pub_4yr) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b07) handle(`R') status(`S')

* 8. Plan: private two-year college. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s08=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_priv_2yr,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b08=ma06_s08==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s08==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_priv_2yr if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_priv_2yr") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_priv_2yr ma_low10, id(U_08) outcome(plan_priv_2yr) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s08) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_priv_2yr ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_08) outcome(plan_priv_2yr) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s08) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_priv_2yr ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_08) outcome(plan_priv_2yr) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s08) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_priv_2yr ma_low10, id(B_08) outcome(plan_priv_2yr) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b08) handle(`R') status(`S')
ma06_fit plan_priv_2yr ma_low10 ma_log2inc, id(BI_08) outcome(plan_priv_2yr) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b08) handle(`R') status(`S')

* 9. Plan: public two-year college. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s09=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_pub_2yr,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b09=ma06_s09==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s09==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_pub_2yr if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_pub_2yr") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_pub_2yr ma_low10, id(U_09) outcome(plan_pub_2yr) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s09) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_pub_2yr ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_09) outcome(plan_pub_2yr) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s09) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_pub_2yr ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_09) outcome(plan_pub_2yr) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s09) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_pub_2yr ma_low10, id(B_09) outcome(plan_pub_2yr) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b09) handle(`R') status(`S')
ma06_fit plan_pub_2yr ma_low10 ma_log2inc, id(BI_09) outcome(plan_pub_2yr) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b09) handle(`R') status(`S')

* 10. Plan: other postsecondary education. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s10=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_other_postsec,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b10=ma06_s10==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s10==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_other_postsec if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_other_postsec") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_other_postsec ma_low10, id(U_10) outcome(plan_other_postsec) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s10) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_other_postsec ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_10) outcome(plan_other_postsec) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s10) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_other_postsec ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_10) outcome(plan_other_postsec) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s10) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_other_postsec ma_low10, id(B_10) outcome(plan_other_postsec) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b10) handle(`R') status(`S')
ma06_fit plan_other_postsec ma_low10 ma_log2inc, id(BI_10) outcome(plan_other_postsec) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b10) handle(`R') status(`S')

* 11. Plan: apprenticeship. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s11=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_apprenticeship,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b11=ma06_s11==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s11==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_apprenticeship if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_apprenticeship") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_apprenticeship ma_low10, id(U_11) outcome(plan_apprenticeship) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s11) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_apprenticeship ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_11) outcome(plan_apprenticeship) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s11) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_apprenticeship ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_11) outcome(plan_apprenticeship) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s11) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_apprenticeship ma_low10, id(B_11) outcome(plan_apprenticeship) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b11) handle(`R') status(`S')
ma06_fit plan_apprenticeship ma_low10 ma_log2inc, id(BI_11) outcome(plan_apprenticeship) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b11) handle(`R') status(`S')

* 12. Plan: employment. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s12=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_work,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b12=ma06_s12==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s12==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_work if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_work") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_work ma_low10, id(U_12) outcome(plan_work) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s12) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_work ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_12) outcome(plan_work) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s12) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_work ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_12) outcome(plan_work) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s12) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_work ma_low10, id(B_12) outcome(plan_work) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b12) handle(`R') status(`S')
ma06_fit plan_work ma_low10 ma_log2inc, id(BI_12) outcome(plan_work) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b12) handle(`R') status(`S')

* 13. Plan: military. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s13=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_military,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b13=ma06_s13==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s13==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_military if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_military") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_military ma_low10, id(U_13) outcome(plan_military) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s13) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_military ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_13) outcome(plan_military) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s13) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_military ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_13) outcome(plan_military) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s13) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_military ma_low10, id(B_13) outcome(plan_military) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b13) handle(`R') status(`S')
ma06_fit plan_military ma_low10 ma_log2inc, id(BI_13) outcome(plan_military) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b13) handle(`R') status(`S')

* 14. Plan: other. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s14=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_other,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b14=ma06_s14==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s14==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_other if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_other") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_other ma_low10, id(U_14) outcome(plan_other) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s14) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_other ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_14) outcome(plan_other) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s14) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_other ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_14) outcome(plan_other) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s14) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_other ma_low10, id(B_14) outcome(plan_other) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b14) handle(`R') status(`S')
ma06_fit plan_other ma_low10 ma_log2inc, id(BI_14) outcome(plan_other) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b14) handle(`R') status(`S')

* 15. Plan: unknown. 2024-25 graduates; reported intentions, not observed enrollment.
gen byte ma06_s15=ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) ///
    & !missing(plan_unknown,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b15=ma06_s15==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s15==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize plan_unknown if ma_primary==1 & (plan_total_count>0 & !missing(plan_total_count)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("plan_unknown") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit plan_unknown ma_low10, id(U_15) outcome(plan_unknown) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s15) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_unknown ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_15) outcome(plan_unknown) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s15) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_unknown ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_15) outcome(plan_unknown) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s15) handle(`R') status(`S') cluster(ma_district)
ma06_fit plan_unknown ma_low10, id(B_15) outcome(plan_unknown) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b15) handle(`R') status(`S')
ma06_fit plan_unknown ma_low10 ma_log2inc, id(BI_15) outcome(plan_unknown) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b15) handle(`R') status(`S')

* 16. Plan: any two- or four-year college. Sum of four mutually exclusive college-plan percentages.
gen byte ma06_s16=ma_primary==1 & (1) ///
    & !missing(ma06_plan_college,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b16=ma06_s16==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s16==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize ma06_plan_college if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("ma06_plan_college") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit ma06_plan_college ma_low10, id(U_16) outcome(ma06_plan_college) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s16) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan_college ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_16) outcome(ma06_plan_college) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s16) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan_college ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_16) outcome(ma06_plan_college) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s16) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan_college ma_low10, id(B_16) outcome(ma06_plan_college) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b16) handle(`R') status(`S')
ma06_fit ma06_plan_college ma_low10 ma_log2inc, id(BI_16) outcome(ma06_plan_college) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b16) handle(`R') status(`S')

* 17. Plan: four-year college. Sum of public and private four-year college-plan percentages.
gen byte ma06_s17=ma_primary==1 & (1) ///
    & !missing(ma06_plan4,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b17=ma06_s17==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s17==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize ma06_plan4 if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("ma06_plan4") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit ma06_plan4 ma_low10, id(U_17) outcome(ma06_plan4) spec(unadjusted) geo(Statewide) family(plans) sample(ma06_s17) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan4 ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_17) outcome(ma06_plan4) spec(adjusted) geo(Statewide) family(plans) sample(ma06_s17) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan4 ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_17) outcome(ma06_plan4) spec(income_adj) geo(Statewide) family(plans) sample(ma06_s17) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan4 ma_low10, id(B_17) outcome(ma06_plan4) spec(BPS_simple) geo(BPS) family(plans) sample(ma06_b17) handle(`R') status(`S')
ma06_fit ma06_plan4 ma_low10 ma_log2inc, id(BI_17) outcome(ma06_plan4) spec(BPS_income) geo(BPS) family(plans) sample(ma06_b17) handle(`R') status(`S')

* 18. Planned minus observed college attendance. School-level percentage-point gap; requires matching graduate counts; does not track individual students.
gen byte ma06_s18=ma_primary==1 & (1) ///
    & !missing(ma06_plan_gap,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b18=ma06_s18==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s18==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize ma06_plan_gap if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("ma06_plan_gap") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit ma06_plan_gap ma_low10, id(U_18) outcome(ma06_plan_gap) spec(unadjusted) geo(Statewide) family(intention_gap) sample(ma06_s18) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan_gap ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_18) outcome(ma06_plan_gap) spec(adjusted) geo(Statewide) family(intention_gap) sample(ma06_s18) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan_gap ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_18) outcome(ma06_plan_gap) spec(income_adj) geo(Statewide) family(intention_gap) sample(ma06_s18) handle(`R') status(`S') cluster(ma_district)
ma06_fit ma06_plan_gap ma_low10, id(B_18) outcome(ma06_plan_gap) spec(BPS_simple) geo(BPS) family(intention_gap) sample(ma06_b18) handle(`R') status(`S')
ma06_fit ma06_plan_gap ma_low10 ma_log2inc, id(BI_18) outcome(ma06_plan_gap) spec(BPS_income) geo(BPS) family(intention_gap) sample(ma06_b18) handle(`R') status(`S')

* 19. Four-year cohort dropout percentage. 2025 four-year cohort; distinct from annual dropout rate.
gen byte ma06_s19=ma_primary==1 & (grad_cohort_num>0 & !missing(grad_cohort_num)) ///
    & !missing(grad_dropout_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b19=ma06_s19==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s19==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize grad_dropout_pct if ma_primary==1 & (grad_cohort_num>0 & !missing(grad_cohort_num)) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("grad_dropout_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit grad_dropout_pct ma_low10, id(U_19) outcome(grad_dropout_pct) spec(unadjusted) geo(Statewide) family(disengagement) sample(ma06_s19) handle(`R') status(`S') cluster(ma_district)
ma06_fit grad_dropout_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_19) outcome(grad_dropout_pct) spec(adjusted) geo(Statewide) family(disengagement) sample(ma06_s19) handle(`R') status(`S') cluster(ma_district)
ma06_fit grad_dropout_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_19) outcome(grad_dropout_pct) spec(income_adj) geo(Statewide) family(disengagement) sample(ma06_s19) handle(`R') status(`S') cluster(ma_district)
ma06_fit grad_dropout_pct ma_low10, id(B_19) outcome(grad_dropout_pct) spec(BPS_simple) geo(BPS) family(disengagement) sample(ma06_b19) handle(`R') status(`S')
ma06_fit grad_dropout_pct ma_low10 ma_log2inc, id(BI_19) outcome(grad_dropout_pct) spec(BPS_income) geo(BPS) family(disengagement) sample(ma06_b19) handle(`R') status(`S')

* 20. Severe chronic absence: 20% of membership days. 2024-25 whole-school population; not only seniors.
gen byte ma06_s20=ma_primary==1 & (1) ///
    & !missing(att_chronic_abs_20pct,ma_low10,ma_log2inc,ma_lntotal,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b20=ma06_s20==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s20==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize att_chronic_abs_20pct if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("att_chronic_abs_20pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit att_chronic_abs_20pct ma_low10, id(U_20) outcome(att_chronic_abs_20pct) spec(unadjusted) geo(Statewide) family(disengagement) sample(ma06_s20) handle(`R') status(`S') cluster(ma_district)
ma06_fit att_chronic_abs_20pct ma_low10 ma_lntotal i.ma_type sel_el_pct sel_swd_pct, id(A_20) outcome(att_chronic_abs_20pct) spec(adjusted) geo(Statewide) family(disengagement) sample(ma06_s20) handle(`R') status(`S') cluster(ma_district)
ma06_fit att_chronic_abs_20pct ma_low10 ma_log2inc ma_lntotal i.ma_type sel_el_pct sel_swd_pct, id(I_20) outcome(att_chronic_abs_20pct) spec(income_adj) geo(Statewide) family(disengagement) sample(ma06_s20) handle(`R') status(`S') cluster(ma_district)
ma06_fit att_chronic_abs_20pct ma_low10, id(B_20) outcome(att_chronic_abs_20pct) spec(BPS_simple) geo(BPS) family(disengagement) sample(ma06_b20) handle(`R') status(`S')
ma06_fit att_chronic_abs_20pct ma_low10 ma_log2inc, id(BI_20) outcome(att_chronic_abs_20pct) spec(BPS_income) geo(BPS) family(disengagement) sample(ma06_b20) handle(`R') status(`S')

* 21. MCAS ELA: average scaled score. 2025 Grade 10 context corroborated at four schools; export lacks explicit grade/group filters.
gen byte ma06_s21=ma_primary==1 & (1) ///
    & !missing(mcas_ela_avg_score,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b21=ma06_s21==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s21==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_ela_avg_score if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_ela_avg_score") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_ela_avg_score ma_low10, id(U_21) outcome(mcas_ela_avg_score) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s21) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_avg_score ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_21) outcome(mcas_ela_avg_score) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s21) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_avg_score ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_21) outcome(mcas_ela_avg_score) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s21) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_avg_score ma_low10, id(B_21) outcome(mcas_ela_avg_score) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b21) handle(`R') status(`S')
ma06_fit mcas_ela_avg_score ma_low10 ma_log2inc, id(BI_21) outcome(mcas_ela_avg_score) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b21) handle(`R') status(`S')

* 22. MCAS ELA: meeting or exceeding expectations. Provisional 2025 Grade 10 context; export grade/group filters unverified; science uses best Grade 9/10 performance.
gen byte ma06_s22=ma_primary==1 & (1) ///
    & !missing(mcas_ela_m_e_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b22=ma06_s22==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s22==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_ela_m_e_pct if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_ela_m_e_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_ela_m_e_pct ma_low10, id(U_22) outcome(mcas_ela_m_e_pct) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s22) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_m_e_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_22) outcome(mcas_ela_m_e_pct) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s22) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_m_e_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_22) outcome(mcas_ela_m_e_pct) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s22) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_m_e_pct ma_low10, id(B_22) outcome(mcas_ela_m_e_pct) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b22) handle(`R') status(`S')
ma06_fit mcas_ela_m_e_pct ma_low10 ma_log2inc, id(BI_22) outcome(mcas_ela_m_e_pct) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b22) handle(`R') status(`S')

* 23. MCAS Mathematics: average scaled score. 2025 Grade 10 context corroborated at four schools; export lacks explicit grade/group filters.
gen byte ma06_s23=ma_primary==1 & (1) ///
    & !missing(mcas_math_avg_score,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b23=ma06_s23==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s23==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_math_avg_score if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_math_avg_score") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_math_avg_score ma_low10, id(U_23) outcome(mcas_math_avg_score) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s23) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_avg_score ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_23) outcome(mcas_math_avg_score) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s23) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_avg_score ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_23) outcome(mcas_math_avg_score) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s23) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_avg_score ma_low10, id(B_23) outcome(mcas_math_avg_score) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b23) handle(`R') status(`S')
ma06_fit mcas_math_avg_score ma_low10 ma_log2inc, id(BI_23) outcome(mcas_math_avg_score) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b23) handle(`R') status(`S')

* 24. MCAS Mathematics: meeting or exceeding expectations. Provisional 2025 Grade 10 context; export grade/group filters unverified; science uses best Grade 9/10 performance.
gen byte ma06_s24=ma_primary==1 & (1) ///
    & !missing(mcas_math_m_e_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b24=ma06_s24==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s24==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_math_m_e_pct if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_math_m_e_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_math_m_e_pct ma_low10, id(U_24) outcome(mcas_math_m_e_pct) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s24) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_m_e_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_24) outcome(mcas_math_m_e_pct) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s24) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_m_e_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_24) outcome(mcas_math_m_e_pct) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s24) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_m_e_pct ma_low10, id(B_24) outcome(mcas_math_m_e_pct) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b24) handle(`R') status(`S')
ma06_fit mcas_math_m_e_pct ma_low10 ma_log2inc, id(BI_24) outcome(mcas_math_m_e_pct) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b24) handle(`R') status(`S')

* 25. MCAS Science: average scaled score. 2025 Grade 10 context corroborated at four schools; export lacks explicit grade/group filters.
gen byte ma06_s25=ma_primary==1 & (1) ///
    & !missing(mcas_sci_avg_score,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b25=ma06_s25==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s25==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_sci_avg_score if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_sci_avg_score") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_sci_avg_score ma_low10, id(U_25) outcome(mcas_sci_avg_score) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s25) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_sci_avg_score ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_25) outcome(mcas_sci_avg_score) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s25) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_sci_avg_score ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_25) outcome(mcas_sci_avg_score) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s25) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_sci_avg_score ma_low10, id(B_25) outcome(mcas_sci_avg_score) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b25) handle(`R') status(`S')
ma06_fit mcas_sci_avg_score ma_low10 ma_log2inc, id(BI_25) outcome(mcas_sci_avg_score) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b25) handle(`R') status(`S')

* 26. MCAS Science: meeting or exceeding expectations. Provisional 2025 Grade 10 context; export grade/group filters unverified; science uses best Grade 9/10 performance.
gen byte ma06_s26=ma_primary==1 & (1) ///
    & !missing(mcas_sci_m_e_pct,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b26=ma06_s26==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s26==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_sci_m_e_pct if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_sci_m_e_pct") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_sci_m_e_pct ma_low10, id(U_26) outcome(mcas_sci_m_e_pct) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s26) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_sci_m_e_pct ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_26) outcome(mcas_sci_m_e_pct) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s26) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_sci_m_e_pct ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_26) outcome(mcas_sci_m_e_pct) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s26) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_sci_m_e_pct ma_low10, id(B_26) outcome(mcas_sci_m_e_pct) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b26) handle(`R') status(`S')
ma06_fit mcas_sci_m_e_pct ma_low10 ma_log2inc, id(BI_26) outcome(mcas_sci_m_e_pct) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b26) handle(`R') status(`S')

* 27. MCAS ELA: average student growth percentile. Provisional 2025 Grade 10 context; export grade/group filters unverified; growth inclusion differs from achievement.
gen byte ma06_s27=ma_primary==1 & (1) ///
    & !missing(mcas_ela_sgp,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b27=ma06_s27==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s27==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_ela_sgp if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_ela_sgp") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_ela_sgp ma_low10, id(U_27) outcome(mcas_ela_sgp) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s27) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_sgp ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_27) outcome(mcas_ela_sgp) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s27) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_sgp ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_27) outcome(mcas_ela_sgp) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s27) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_ela_sgp ma_low10, id(B_27) outcome(mcas_ela_sgp) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b27) handle(`R') status(`S')
ma06_fit mcas_ela_sgp ma_low10 ma_log2inc, id(BI_27) outcome(mcas_ela_sgp) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b27) handle(`R') status(`S')

* 28. MCAS MATH: average student growth percentile. Provisional 2025 Grade 10 context; export grade/group filters unverified; growth inclusion differs from achievement.
gen byte ma06_s28=ma_primary==1 & (1) ///
    & !missing(mcas_math_sgp,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b28=ma06_s28==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s28==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize mcas_math_sgp if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("mcas_math_sgp") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit mcas_math_sgp ma_low10, id(U_28) outcome(mcas_math_sgp) spec(unadjusted) geo(Statewide) family(mcas) sample(ma06_s28) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_sgp ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_28) outcome(mcas_math_sgp) spec(adjusted) geo(Statewide) family(mcas) sample(ma06_s28) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_sgp ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_28) outcome(mcas_math_sgp) spec(income_adj) geo(Statewide) family(mcas) sample(ma06_s28) handle(`R') status(`S') cluster(ma_district)
ma06_fit mcas_math_sgp ma_low10, id(B_28) outcome(mcas_math_sgp) spec(BPS_simple) geo(BPS) family(mcas) sample(ma06_b28) handle(`R') status(`S')
ma06_fit mcas_math_sgp ma_low10 ma_log2inc, id(BI_28) outcome(mcas_math_sgp) spec(BPS_income) geo(BPS) family(mcas) sample(ma06_b28) handle(`R') status(`S')

* 29. SAT mathematics. 2024-25 participating test takers; selected population.
gen byte ma06_s29=ma_primary==1 & (1) ///
    & !missing(sat_math,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b29=ma06_s29==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s29==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize sat_math if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("sat_math") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit sat_math ma_low10, id(U_29) outcome(sat_math) spec(unadjusted) geo(Statewide) family(sat) sample(ma06_s29) handle(`R') status(`S') cluster(ma_district)
ma06_fit sat_math ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_29) outcome(sat_math) spec(adjusted) geo(Statewide) family(sat) sample(ma06_s29) handle(`R') status(`S') cluster(ma_district)
ma06_fit sat_math ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_29) outcome(sat_math) spec(income_adj) geo(Statewide) family(sat) sample(ma06_s29) handle(`R') status(`S') cluster(ma_district)
ma06_fit sat_math ma_low10, id(B_29) outcome(sat_math) spec(BPS_simple) geo(BPS) family(sat) sample(ma06_b29) handle(`R') status(`S')
ma06_fit sat_math ma_low10 ma_log2inc, id(BI_29) outcome(sat_math) spec(BPS_income) geo(BPS) family(sat) sample(ma06_b29) handle(`R') status(`S')

* 30. SAT reading and writing. 2024-25 participating test takers; selected population.
gen byte ma06_s30=ma_primary==1 & (1) ///
    & !missing(sat_reading_writing,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b30=ma06_s30==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s30==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize sat_reading_writing if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("sat_reading_writing") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit sat_reading_writing ma_low10, id(U_30) outcome(sat_reading_writing) spec(unadjusted) geo(Statewide) family(sat) sample(ma06_s30) handle(`R') status(`S') cluster(ma_district)
ma06_fit sat_reading_writing ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_30) outcome(sat_reading_writing) spec(adjusted) geo(Statewide) family(sat) sample(ma06_s30) handle(`R') status(`S') cluster(ma_district)
ma06_fit sat_reading_writing ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_30) outcome(sat_reading_writing) spec(income_adj) geo(Statewide) family(sat) sample(ma06_s30) handle(`R') status(`S') cluster(ma_district)
ma06_fit sat_reading_writing ma_low10, id(B_30) outcome(sat_reading_writing) spec(BPS_simple) geo(BPS) family(sat) sample(ma06_b30) handle(`R') status(`S')
ma06_fit sat_reading_writing ma_low10 ma_log2inc, id(BI_30) outcome(sat_reading_writing) spec(BPS_income) geo(BPS) family(sat) sample(ma06_b30) handle(`R') status(`S')

* 31. AP unique exam-taker count. 2024-25 exam-taking volume; grade universe unverified; school-size covariate, not a participation-rate denominator.
gen byte ma06_s31=ma_primary==1 & (1) ///
    & !missing(ap_part_tests_takers,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b31=ma06_s31==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s31==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize ap_part_tests_takers if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("ap_part_tests_takers") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit ap_part_tests_takers ma_low10, id(U_31) outcome(ap_part_tests_takers) spec(unadjusted) geo(Statewide) family(ap) sample(ma06_s31) handle(`R') status(`S') cluster(ma_district)
ma06_fit ap_part_tests_takers ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_31) outcome(ap_part_tests_takers) spec(adjusted) geo(Statewide) family(ap) sample(ma06_s31) handle(`R') status(`S') cluster(ma_district)
ma06_fit ap_part_tests_takers ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_31) outcome(ap_part_tests_takers) spec(income_adj) geo(Statewide) family(ap) sample(ma06_s31) handle(`R') status(`S') cluster(ma_district)
ma06_fit ap_part_tests_takers ma_low10, id(B_31) outcome(ap_part_tests_takers) spec(BPS_simple) geo(BPS) family(ap) sample(ma06_b31) handle(`R') status(`S')
ma06_fit ap_part_tests_takers ma_low10 ma_log2inc, id(BI_31) outcome(ap_part_tests_takers) spec(BPS_income) geo(BPS) family(ap) sample(ma06_b31) handle(`R') status(`S')

* 32. Reported pathways/program count. 2025-26 grades 9-12 plus SP; not verified unique students; 2024-25 size is a lagged context control.
gen byte ma06_s32=ma_primary==1 & (1) ///
    & !missing(path_total,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b32=ma06_s32==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s32==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize path_total if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("path_total") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit path_total ma_low10, id(U_32) outcome(path_total) spec(unadjusted) geo(Statewide) family(pathways) sample(ma06_s32) handle(`R') status(`S') cluster(ma_district)
ma06_fit path_total ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_32) outcome(path_total) spec(adjusted) geo(Statewide) family(pathways) sample(ma06_s32) handle(`R') status(`S') cluster(ma_district)
ma06_fit path_total ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_32) outcome(path_total) spec(income_adj) geo(Statewide) family(pathways) sample(ma06_s32) handle(`R') status(`S') cluster(ma_district)
ma06_fit path_total ma_low10, id(B_32) outcome(path_total) spec(BPS_simple) geo(BPS) family(pathways) sample(ma06_b32) handle(`R') status(`S')
ma06_fit path_total ma_low10 ma_log2inc, id(BI_32) outcome(path_total) spec(BPS_income) geo(BPS) family(pathways) sample(ma06_b32) handle(`R') status(`S')

* 33. Published pathways/program percentage. 2025-26 later context; published values above 100 retained and flagged; separate exclusion sensitivity.
gen byte ma06_s33=ma_primary==1 & (1) ///
    & !missing(path_pct_all_students,ma_low10,ma_log2inc,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_b33=ma06_s33==1 & ma_bps==1
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly count if ma06_s33==1 & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        local nm=r(N)
        quietly summarize path_pct_all_students if ma_primary==1 & (1) & ma_ses3==`g' & ("`geo'"=="Statewide" | ma_bps==1)
        post `D' ("path_pct_all_students") ("`geo'") (`g') (`ne') (r(N)) (`nm') (r(mean)) (r(sd)) (r(min)) (r(max))
    }
}
ma06_fit path_pct_all_students ma_low10, id(U_33) outcome(path_pct_all_students) spec(unadjusted) geo(Statewide) family(pathways) sample(ma06_s33) handle(`R') status(`S') cluster(ma_district)
ma06_fit path_pct_all_students ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(A_33) outcome(path_pct_all_students) spec(adjusted) geo(Statewide) family(pathways) sample(ma06_s33) handle(`R') status(`S') cluster(ma_district)
ma06_fit path_pct_all_students ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(I_33) outcome(path_pct_all_students) spec(income_adj) geo(Statewide) family(pathways) sample(ma06_s33) handle(`R') status(`S') cluster(ma_district)
ma06_fit path_pct_all_students ma_low10, id(B_33) outcome(path_pct_all_students) spec(BPS_simple) geo(BPS) family(pathways) sample(ma06_b33) handle(`R') status(`S')
ma06_fit path_pct_all_students ma_low10 ma_log2inc, id(BI_33) outcome(path_pct_all_students) spec(BPS_income) geo(BPS) family(pathways) sample(ma06_b33) handle(`R') status(`S')

* FAFSA: preserve original screened rate, fixed groups and denominators.
gen byte ma06_ff=ma_primary==1 & !missing(ma_fafsa,ma_low10,ma_ln912,ma_type,sel_el_pct,sel_swd_pct,ma_district)
gen byte ma06_fc=ma06_ff==1 & !missing(ma_log2inc)
gen byte ma06_fb=ma06_ff==1 & ma_bps==1
gen byte ma06_fbi=ma06_fc==1 & ma_bps==1
gen byte ma06_fnx=ma06_fb==1 & ma_bps_exam==0
quietly summarize sel_low_income_pct if ma_primary==1, detail
local fixed_p25=r(p25)
local fixed_p75=r(p75)
local fixed_iqr=(r(p75)-r(p25))/10
display as text "Fixed statewide low-income IQR in ten-point units: `fixed_iqr'"

ma06_fit ma_fafsa ma_low10, id(F_U_full) outcome(ma_fafsa) spec(unadjusted) geo(Statewide) family(fafsa) sample(ma06_ff) handle(`R') status(`S') cluster(ma_district)
lincom ma_low10
post `F' ("F_U_full") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))
lincom ma_low10*(`fixed_iqr')
post `F' ("F_U_full") ("Fixed statewide low-income IQR contrast") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(F_A_full) outcome(ma_fafsa) spec(adjusted) geo(Statewide) family(fafsa) sample(ma06_ff) handle(`R') status(`S') cluster(ma_district)
lincom ma_low10
post `F' ("F_A_full") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))
lincom ma_low10*(`fixed_iqr')
post `F' ("F_A_full") ("Fixed statewide low-income IQR contrast") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10, id(F_U_common) outcome(ma_fafsa) spec(unadjusted) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom ma_low10
post `F' ("F_U_common") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))
lincom ma_low10*(`fixed_iqr')
post `F' ("F_U_common") ("Fixed statewide low-income IQR contrast") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10 ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(F_A_common) outcome(ma_fafsa) spec(adjusted) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom ma_low10
post `F' ("F_A_common") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))
lincom ma_low10*(`fixed_iqr')
post `F' ("F_A_common") ("Fixed statewide low-income IQR contrast") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(F_I_common) outcome(ma_fafsa) spec(income_adj) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom ma_low10
post `F' ("F_I_common") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))
lincom ma_low10*(`fixed_iqr')
post `F' ("F_I_common") ("Fixed statewide low-income IQR contrast") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses3, id(F_G3_U) outcome(ma_fafsa) spec(tercile_raw) geo(Statewide) family(fafsa) sample(ma06_ff) handle(`R') status(`S') cluster(ma_district)
lincom -1*3.ma_ses3
post `F' ("F_G3_U") ("Highest minus lowest low-income group") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses4, id(F_G4_U) outcome(ma_fafsa) spec(quartile_raw) geo(Statewide) family(fafsa) sample(ma06_ff) handle(`R') status(`S') cluster(ma_district)
lincom -1*4.ma_ses4
post `F' ("F_G4_U") ("Highest minus lowest low-income group") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses3, id(F_G3_C) outcome(ma_fafsa) spec(tercile_common) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom -1*3.ma_ses3
post `F' ("F_G3_C") ("Highest minus lowest low-income group") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses4, id(F_G4_C) outcome(ma_fafsa) spec(quartile_common) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom -1*4.ma_ses4
post `F' ("F_G4_C") ("Highest minus lowest low-income group") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses3 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(F_G3_I) outcome(ma_fafsa) spec(tercile_inc) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom -1*3.ma_ses3
post `F' ("F_G3_I") ("Highest minus lowest low-income group") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses4 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, id(F_G4_I) outcome(ma_fafsa) spec(quartile_inc) geo(Statewide) family(fafsa) sample(ma06_fc) handle(`R') status(`S') cluster(ma_district)
lincom -1*4.ma_ses4
post `F' ("F_G4_I") ("Highest minus lowest low-income group") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10, id(F_BPS) outcome(ma_fafsa) spec(BPS_simple) geo(BPS) family(fafsa) sample(ma06_fb) handle(`R') status(`S')
lincom ma_low10
post `F' ("F_BPS") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10 ma_log2inc, id(F_BPS_I) outcome(ma_fafsa) spec(BPS_income) geo(BPS) family(fafsa) sample(ma06_fbi) handle(`R') status(`S')
lincom ma_low10
post `F' ("F_BPS_I") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ma_low10, id(F_BPS_NX) outcome(ma_fafsa) spec(BPS_noexam) geo(BPS) family(fafsa) sample(ma06_fnx) handle(`R') status(`S')
lincom ma_low10
post `F' ("F_BPS_NX") ("Per 10-point higher student low-income share") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses3, id(F_BPS_G3) outcome(ma_fafsa) spec(BPS_group_raw) geo(BPS) family(fafsa) sample(ma06_fb) handle(`R') status(`S')
lincom -1*2.ma_ses3
post `F' ("F_BPS_G3") ("Highest minus middle low-income group: BPS") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

ma06_fit ma_fafsa ib1.ma_ses3 ma_log2inc, id(F_BPS_G3_I) outcome(ma_fafsa) spec(BPS_group_inc) geo(BPS) family(fafsa) sample(ma06_fbi) handle(`R') status(`S')
lincom -1*2.ma_ses3
post `F' ("F_BPS_G3_I") ("Highest minus middle low-income group: BPS") (r(estimate)) (r(se)) (r(lb)) (r(ub)) (r(p)) (e(N))

* Predeclared pathways sensitivity; never cap published values at 100.
gen byte ma06_pclean=ma06_s33==1 & ma06_path_gt100==0
ma06_fit path_pct_all_students ma_low10 ma_log2inc ma_ln912 i.ma_type sel_el_pct sel_swd_pct, ///
    id(P_no100) outcome(path_pct_all_students) spec(exclude_gt100) geo(Statewide) family(pathways) ///
    sample(ma06_pclean) handle(`R') status(`S') cluster(ma_district)
postclose `R'
postclose `S'
postclose `D'
postclose `F'

sort school_code
save "$MA06/06_analysis_ready.dta", replace
preserve
keep school_code school_name ma_primary ma_bps ma_bps_exam sel_low_income_pct ///
    acs_median_hh_income ma_ses3 ma_ses4 ma06_* college_attend_pct ///
    college_priv_2yr_pct college_priv_4yr_pct college_pub_2yr_pct college_pub_4yr_pct ///
    plan_* grad_dropout_pct att_chronic_abs_20pct mcas_* sat_math sat_reading_writing ///
    ap_part_tests_takers path_total path_pct_all_students
export delimited using "$MA06/06_school_data.csv", nolabel replace
restore

* Labels and population notes travel with the numeric exports.
preserve
import delimited "$MA_PROJECT/data/06_outcome_catalogue.csv", varnames(1) stringcols(_all) clear
isid outcome
tempfile catalogue
save "`catalogue'"
use "$MA06/06_regression_coefficients.dta", clear
merge m:1 outcome using "`catalogue'", keep(master match) nogen
export delimited using "$MA06/06_regression_coefficients.csv", replace
keep if term=="ma_low10" & family!="fafsa" & specification!="exclude_gt100"
assert !missing(p)
* Family-wise Holm for each specification/geography, then a stricter global check.
bysort geography specification family (p outcome): gen int family_rank=_n
destring family_tests_planned, replace
gen int family_tests=family_tests_planned
gen double p_holm_family=min(1,(family_tests-family_rank+1)*p)
by geography specification family: replace p_holm_family=max(p_holm_family,p_holm_family[_n-1]) if _n>1
bysort geography specification (p outcome): gen int global_rank=_n
gen int global_tests=33
gen double p_holm_global=min(1,(global_tests-global_rank+1)*p)
by geography specification: replace p_holm_global=max(p_holm_global,p_holm_global[_n-1]) if _n>1
gen str180 inference_note="Exploratory outcomes; nominal CIs; Holm uses planned family sizes and 33 outcomes per specification/geography, with skipped tests treated as p=1; associations"
sort geography specification family outcome
save "$MA06/06_ses_results.dta", replace
export delimited using "$MA06/06_ses_results.csv", replace
use "$MA06/06_model_status.dta", clear
merge m:1 outcome using "`catalogue'", keep(master match) nogen
export delimited using "$MA06/06_model_status.csv", replace
use "$MA06/06_outcomes_by_ses.dta", clear
merge m:1 outcome using "`catalogue'", assert(match) nogen
gen long n_missing=n_eligible-n_available
export delimited using "$MA06/06_outcomes_by_ses.csv", replace
use "$MA06/06_fafsa_contrasts.dta", clear
gen double fixed_statewide_li_p25=`fixed_p25'
gen double fixed_statewide_li_p75=`fixed_p75'
gen str100 direction="Higher low-income share minus lower share; BPS groups compare highest with middle"
gen str150 interpretation="Different contrasts/geographies are different questions; no sorting or selecting for largest gap; nominal 95% confidence intervals"
export delimited using "$MA06/06_fafsa_contrasts.csv", replace
restore

* Independent numerical validation for all fitted continuous SES coefficients.
preserve
import delimited "$MA_PROJECT/data/06_expected_ses_coefficients.csv", varnames(1) asdouble clear
isid model term
tempfile reference
save "`reference'"
use "$MA06/06_regression_coefficients.dta", clear
keep if inlist(term,"ma_low10","ma_log2inc") | regexm(term,"^[234][.]ma_ses[34]$")
isid model term
merge 1:1 model term using "`reference'", gen(reference_match)
export delimited using "$MA06/06_independent_comparison.csv", replace
assert reference_match==3
assert n==ref_n & n_clusters==ref_n_clusters & df==ref_df
foreach v in b se ci_low ci_high p r2 {
    gen double difference_`v'=abs(`v'-ref_`v')
    assert difference_`v'<1e-5+1e-7*abs(ref_`v')
    quietly summarize difference_`v'
    display as text "Independent reference: maximum `v' difference = " %12.8g r(max)
}
export delimited using "$MA06/06_independent_comparison.csv", replace
display as result "INDEPENDENT NUMERICAL CHECK PASSED"
restore
display as result "06 ANALYSIS COMPLETED: additional outcomes and FAFSA comparisons saved."
display as text "Send 06_additional_models.log, 06_ses_results.csv, 06_fafsa_contrasts.csv and 06_model_status.csv."
display as text "This does not resolve ACS vintage, all MCAS filters, AP grade universe or program-count definitions."
log close
* END OF 06 ANALYSIS
