/* Website figures and tables from verified stages 03/06, 12 October 2026.
   Stata 16+, built-in commands only. Run the WHOLE file on your Mac.
   Reads existing results; no models, SES groups or source files are changed.
   New outputs: seven PNG/SVG chart pairs and four CSV tables.
*/
version 16.0
clear all
set more off
set varabbrev off
set linesize 160
global MA_PROJECT "/Users/benw/Desktop/useful/MA_SES_Project"
global MA03 "$MA_PROJECT/output/03_analysis"
global MA06 "$MA_PROJECT/output/06_additional_models"
global MA07 "$MA_PROJECT/output/07_website_results"
cd "$MA_PROJECT"
capture mkdir "$MA07"
capture mkdir "$MA07/figures"
capture log close _all
log using "$MA07/07_website_results.log", text replace
display as result "07 WEBSITE EXPORT STARTED"
confirm file "$MA03/03_analysis_ready.dta"
confirm file "$MA06/06_regression_coefficients.csv"
confirm file "$MA06/06_outcomes_by_ses.csv"
confirm file "$MA06/06_ses_results.csv"
confirm file "$MA06/06_SES_group_test.log"
set scheme s2color

* Verify the previously run joint test; annotations below are its rounded output.
tempname JL
file open `JL' using "$MA06/06_SES_group_test.log", read text
local saw_joint=0
local saw_joint_p=0
local saw_endpoint=0
file read `JL' joint_line
while r(eof)==0 {
    local compact=subinstr(`"`joint_line'"'," ","",.)
    if strpos(`"`compact'"',"F(2,293)=8.65")>0 local saw_joint=1
    if strpos(`"`compact'"',"Prob>F=0.0002")>0 local saw_joint_p=1
    if strpos(`"`compact'"',"9.00244")>0 & ///
        strpos(`"`compact'"',".174983")>0 & ///
        strpos(`"`compact'"',"17.8299")>0 local saw_endpoint=1
    file read `JL' joint_line
}
file close `JL'
assert `saw_joint'==1 & `saw_joint_p'==1 & `saw_endpoint'==1
display as text "Verified saved joint test: F(2,293)=8.65; p=0.0002."

* 1. Raw FAFSA means and availability use all eligible reporting schools.
use "$MA03/03_analysis_ready.dta", clear
assert _N==415
isid school_code
assert strlen(school_code)==8
quietly count if ma_primary==1
assert r(N)==407
quietly count if ma_primary==1 & ma_bps==1
assert r(N)==31
quietly count if ma_primary==1 & ma_bps==1 & ma_bps_exam==1
assert r(N)==3
assert ma_ses3==2 if ma_primary==1 & ma_bps_exam==1
quietly count if ma_primary==1 & ma_bps==1 & ma_ses3==2 & school_code=="00350546"
assert r(N)==1
assert !missing(ma_ses3,grade12_enrollment,sel_low_income_pct) ///
    & grade12_enrollment>0 if ma_primary==1
assert inrange(ma_ses3,1,3) if ma_primary==1
assert sel_low_income_pct>=59.8 if ma_primary==1 & ma_ses3==1
assert sel_low_income_pct>=28.9 & sel_low_income_pct<59.8 if ma_primary==1 & ma_ses3==2
assert sel_low_income_pct<28.9 if ma_primary==1 & ma_ses3==3
assert inrange(ma_fafsa,0,100) if !missing(ma_fafsa)
assert src_cycle=="2025-26" & src_cutoff=="2025-05-31"
gen byte ma07_usable=!missing(ma_fafsa)
assert ma07_usable==ma_fafsa_senior_usable
quietly count if ma_primary==1 & ma07_usable==1
assert r(N)==356
quietly count if ma_primary==1 & ma_bps==1 & ma07_usable==1
assert r(N)==27
tempfile fafsa_groups outcomes_groups fafsa_models
tempname FG
postfile `FG' str12 geography byte ses_group ///
    long(n_eligible n_usable) double(mean sd minimum maximum ///
    seniors_total seniors_in_usable_schools) using "`fafsa_groups'", replace
foreach geo in Statewide BPS {
    forvalues g=1/3 {
        quietly count if ma_primary==1 & ma_ses3==`g' ///
            & ("`geo'"=="Statewide" | ma_bps==1)
        local ne=r(N)
        quietly summarize ma_fafsa if ma_primary==1 & ma_ses3==`g' ///
            & ("`geo'"=="Statewide" | ma_bps==1)
        local nu=r(N)
        local mm=r(mean)
        local ss=r(sd)
        local mn=r(min)
        local mx=r(max)
        local st=0
        local su=0
        if `ne'>0 {
            quietly summarize grade12_enrollment if ma_primary==1 & ma_ses3==`g' ///
                & ("`geo'"=="Statewide" | ma_bps==1)
            local st=r(sum)
        }
        if `nu'>0 {
            quietly summarize grade12_enrollment if ma_primary==1 & ma_ses3==`g' ///
                & ma07_usable==1 & ("`geo'"=="Statewide" | ma_bps==1)
            local su=r(sum)
        }
        post `FG' ("`geo'") (`g') (`ne') (`nu') (`mm') (`ss') (`mn') (`mx') (`st') (`su')
    }
}
postclose `FG'
use "`fafsa_groups'", clear
assert _N==6
isid geography ses_group
gen str32 ses_label=""
replace ses_label="Higher low-income share" if ses_group==1
replace ses_label="Middle low-income share" if ses_group==2
replace ses_label="Lower low-income share" if ses_group==3
gen double statewide_low_income_min=cond(ses_group==1,59.8,cond(ses_group==2,28.9,5.1))
gen double statewide_low_income_max=cond(ses_group==1,95.8,cond(ses_group==2,59.5,28.6))
gen long n_missing=n_eligible-n_usable
gen double school_available_pct=100*n_usable/n_eligible if n_eligible>0
gen double school_unavailable_pct=100*n_missing/n_eligible if n_eligible>0
gen double senior_school_coverage_pct=100*seniors_in_usable_schools/seniors_total if seniors_total>0
gen str100 coverage_note="Senior coverage is enrollment at usable-rate schools, not individual FAFSA matching."
replace coverage_note="No BPS schools in this statewide group; means and percentages are undefined." if n_eligible==0
gen str150 population_note="FAFSA through May 31, 2025, 2025-26 aid cycle / October 2024 enrolled seniors; screened school estimate."
gen str100 source_note="U.S. ED/FSA historical May 2026 release; Massachusetts DESE 2024-25 enrollment."
gen str100 comparison_note="Unweighted school means; fixed statewide low-income terciles; missing estimates are not zero."
gen str20 descriptive_units="percent"
assert n_eligible==n_usable+n_missing
assert n_eligible==cond(ses_group==1,137,135) if geography=="Statewide"
assert n_usable==cond(ses_group==1,92,cond(ses_group==2,131,133)) if geography=="Statewide"
assert n_eligible==cond(ses_group==1,27,cond(ses_group==2,4,0)) if geography=="BPS"
assert n_usable==cond(ses_group==1,23,cond(ses_group==2,4,0)) if geography=="BPS"
assert inrange(mean,0,100) if n_usable>0
assert inrange(school_available_pct,0,100) if n_eligible>0
assert inrange(senior_school_coverage_pct,0,100) if seniors_total>0
assert missing(mean) & missing(school_available_pct) & missing(senior_school_coverage_pct) if n_eligible==0
sort geography ses_group
order geography ses_group ses_label statewide_low_income_min statewide_low_income_max ///
    n_eligible n_usable n_missing mean sd minimum maximum school_available_pct ///
    school_unavailable_pct seniors_total seniors_in_usable_schools senior_school_coverage_pct
export delimited using "$MA07/07_fafsa_by_ses.csv", nolabel replace
save "`fafsa_groups'", replace

foreach geo in Statewide BPS {
    preserve
    keep if geography=="`geo'"
    sort ses_group
    forvalues g=1/3 {
        local nn`g'=n_usable[`g']
        local ee`g'=n_eligible[`g']
    }
    label define ma07_fafsa_group 1 "Higher share (N=`nn1')" ///
        2 "Middle share (N=`nn2')" 3 "Lower share (N=`nn3')", replace
    label values ses_group ma07_fafsa_group
    local geonote "407 eligible schools; reporting-school counts appear in the labels."
    if "`geo'"=="BPS" local geonote "No lower-share BPS group. Middle four: three exam schools and Boston Arts Academy."
    graph bar (asis) mean if n_eligible>0, over(ses_group,label(labsize(small))) ///
        bar(1,color(navy)) blabel(bar,format(%4.1f) position(inside) color(white) size(medsmall)) ///
        yscale(range(0 100)) ylabel(0(20)100,angle(horizontal)) ///
        ytitle("Mean school estimated FAFSA rate (%)") ///
        title("`geo': estimated FAFSA rates",size(medsmall)) ///
        subtitle("Fixed groups defined by student low-income share",size(small)) ///
        note("Unweighted school means; N counts schools with usable estimates." ///
             "`geonote'" ///
             "FAFSA through May 31, 2025 (2025-26 aid) / October 2024 enrolled seniors." ///
             "Federal applicant population differs from enrolled seniors; screened estimates." ///
             "Sources: U.S. ED/FSA historical May 2026 release and Massachusetts DESE.",size(vsmall)) ///
        xsize(9) ysize(6.5) graphregion(color(white)) name(ma07_`geo'_fafsa,replace)
    graph export "$MA07/figures/07_`geo'_fafsa_ses3.png", width(1800) replace
    graph export "$MA07/figures/07_`geo'_fafsa_ses3.svg", replace
    label define ma07_available 1 "Higher share (`nn1'/`ee1')" ///
        2 "Middle share (`nn2'/`ee2')" 3 "Lower share (`nn3'/`ee3')", replace
    label values ses_group ma07_available
    graph bar (asis) school_available_pct if n_eligible>0, ///
        over(ses_group,label(labsize(small))) bar(1,color(navy)) ///
        blabel(bar,format(%4.1f) position(inside) color(white) size(medsmall)) ///
        yscale(range(0 100)) ylabel(0(20)100,angle(horizontal)) ///
        ytitle("Schools with usable estimates (%)") title("`geo'",size(medsmall)) ///
        xsize(6) ysize(4.5) graphregion(color(white)) name(ma07_av_`geo',replace)
    restore
}
graph combine ma07_av_Statewide ma07_av_BPS, cols(2) ycommon iscale(1) ///
    title("FAFSA data availability across SES groups",size(medsmall)) ///
    subtitle("Labels show usable / eligible schools; share means student low-income share",size(small)) ///
    note("Unavailable includes suppression, unmatched records and screened source issues; it is not zero completion." ///
         "No BPS schools belong to the lower-share statewide group; its availability percentage is undefined." ///
         "Sources: verified merged school sample, U.S. ED/FSA and Massachusetts DESE.",size(vsmall)) ///
    xsize(12) ysize(6.5) graphregion(color(white)) name(ma07_availability,replace)
graph export "$MA07/figures/07_fafsa_availability.png", width(2400) replace
graph export "$MA07/figures/07_fafsa_availability.svg", replace

* 2. Export existing common-sample FAFSA coefficients, not new regressions.
import delimited using "$MA06/06_regression_coefficients.csv", clear varnames(1) asdouble
isid model term
keep if (inlist(model,"F_U_common","F_A_common","F_I_common") & term=="ma_low10") ///
    | (inlist(model,"F_G3_C","F_G3_I") & inlist(term,"2.ma_ses3","3.ma_ses3"))
assert _N==7
assert outcome=="ma_fafsa" & geography=="Statewide" & vce=="district clustered"
assert n==355 & n_clusters==294 & df==293
assert !missing(b,se,ci_low,ci_high,p) & se>0
assert ci_low<=b & b<=ci_high
assert inrange(p,0,1)
assert abs(b-9.002440133738)<1e-6 if model=="F_G3_I" & term=="3.ma_ses3"
assert abs(ci_low-.174983040996)<1e-5 if model=="F_G3_I" & term=="3.ma_ses3"
assert abs(ci_high-17.82989722648)<1e-5 if model=="F_G3_I" & term=="3.ma_ses3"
gen str90 model_label=""
replace model_label="Unadjusted; continuous low-income share" if model=="F_U_common"
replace model_label="Adjusted; continuous low-income share" if model=="F_A_common"
replace model_label="Adjusted plus campus income; continuous low-income share" if model=="F_I_common"
replace model_label="Unadjusted terciles; income-complete sample" if model=="F_G3_C"
replace model_label="Adjusted terciles plus campus income" if model=="F_G3_I"
replace outcome_label="Estimated FAFSA completion rate"
gen str90 contrast_label="Per 10 percentage points higher student low-income share"
replace contrast_label="Middle low-income-share group minus higher-share group" if term=="2.ma_ses3"
replace contrast_label="Lower low-income-share group minus higher-share group" if term=="3.ma_ses3"
recast str40 units
replace units="percentage-point difference"
gen str150 control_note="None"
replace control_note="Log grades 9-12 enrollment, school type, English-learner share and disability share" if model=="F_A_common"
replace control_note="Log campus-tract income, log grades 9-12 enrollment, school type, EL and disability shares" if inlist(model,"F_I_common","F_G3_I")
gen str150 context_note="Same 355 schools; campus-tract income describes school location, not enrolled students' home neighborhoods."
gen str140 ci_note="District-clustered nominal 95% confidence intervals and nominal p-values; school-level associations, not causal effects."
gen double group_joint_F=8.65 if model=="F_G3_I"
gen double group_joint_p=.0002 if model=="F_G3_I"
gen byte group_joint_df1=2 if model=="F_G3_I"
gen int group_joint_df2=293 if model=="F_G3_I"
gen str130 group_joint_source=""
replace group_joint_source="Rounded Stata joint test of 2.ma_ses3 and 3.ma_ses3; verified 06_SES_group_test.log" if model=="F_G3_I"
replace population_note="FAFSA through May 31, 2025, 2025-26 aid / October 2024 enrolled seniors; screened estimate"
sort model term
order model model_label specification term contrast_label b se ci_low ci_high p n n_clusters ///
    df units control_note group_joint_F group_joint_p group_joint_df1 group_joint_df2 group_joint_source
export delimited using "$MA07/07_fafsa_regression_table.csv", nolabel replace
save "`fafsa_models'", replace

preserve
keep if model=="F_G3_I"
assert _N==2
gen byte plot_order=cond(term=="2.ma_ses3",1,2)
label define ma07_adjusted_group 1 "Middle share minus higher share" ///
    2 "Lower share minus higher share", replace
label values plot_order ma07_adjusted_group
twoway (rcap ci_low ci_high plot_order,horizontal lcolor(navy)) ///
    (scatter plot_order b,mcolor(navy) msymbol(O)), ///
    yscale(reverse) ylabel(1/2,valuelabel angle(horizontal) labsize(small)) ///
    ytitle("") xtitle("Estimated FAFSA difference (percentage points)",size(small)) ///
    xlabel(-10(5)20) xline(0,lcolor(gs8) lpattern(dash)) legend(off) ///
    title("Adjusted FAFSA differences across SES groups",size(medsmall)) ///
    subtitle("Reference: higher low-income share; N=355 schools, 294 districts",size(small)) ///
    note("Joint test of both SES group terms: F(2,293)=8.65; p=0.0002 (verified saved Stata test)." ///
         "Dots and lines: group differences and nominal district-clustered 95% confidence intervals." ///
         "Controls: campus-tract income, school size/type, English-learner and disability shares." ///
         "Campus income describes school location. These are school-level associations, not causal effects.",size(vsmall)) ///
    xsize(10) ysize(6.5) graphregion(color(white)) name(ma07_adjusted_groups,replace)
graph export "$MA07/figures/07_fafsa_adjusted_groups.png", width(2000) replace
graph export "$MA07/figures/07_fafsa_adjusted_groups.svg", replace
restore
preserve
keep if inlist(model,"F_U_common","F_A_common","F_I_common")
assert _N==3
gen byte plot_order=cond(model=="F_U_common",1,cond(model=="F_A_common",2,3))
label define ma07_continuous 1 "Unadjusted" 2 "Adjusted" 3 "Adjusted + campus income", replace
label values plot_order ma07_continuous
twoway (rcap ci_low ci_high plot_order,horizontal lcolor(navy)) ///
    (scatter plot_order b,mcolor(navy) msymbol(O)), ///
    yscale(reverse) ylabel(1/3,valuelabel angle(horizontal) labsize(small)) ///
    ytitle("") xtitle("FAFSA percentage-point difference per 10 pp higher low-income share",size(small)) ///
    xlabel(-5(1)1) xline(0,lcolor(gs8) lpattern(dash)) legend(off) ///
    title("FAFSA continuous models on the same schools",size(medsmall)) ///
    subtitle("All three models: N=355 schools and 294 districts",size(small)) ///
    note("Dots and lines: continuous associations and nominal district-clustered 95% confidence intervals." ///
         "Adjusted model: school size/type, English-learner and disability shares; third model adds campus income." ///
         "Campus-tract income describes school location, not student residence. Associations are not causal.",size(vsmall)) ///
    xsize(10) ysize(6.5) graphregion(color(white)) name(ma07_continuous_models,replace)
graph export "$MA07/figures/07_fafsa_continuous_models.png", width(2000) replace
graph export "$MA07/figures/07_fafsa_continuous_models.svg", replace
restore

* 3. Preserve all 198 outcome summaries; plot two outcomes with clear populations.
import delimited using "$MA06/06_outcomes_by_ses.csv", clear varnames(1) asdouble
assert _N==198
isid outcome geography ses_group
assert inlist(geography,"Statewide","BPS") & inrange(ses_group,1,3)
assert n_eligible>=n_available & n_available>=n_common & n_common>=0
assert n_missing==n_eligible-n_available
assert n_eligible==cond(ses_group==1,137,135) if geography=="Statewide"
assert n_eligible==cond(ses_group==1,27,cond(ses_group==2,4,0)) if geography=="BPS"
assert !missing(mean,minimum,maximum) & minimum<=mean & mean<=maximum if n_available>0
assert missing(mean) & missing(sd) & missing(minimum) & missing(maximum) if n_available==0
gen str40 descriptive_units=units
replace descriptive_units="percent" if units=="percentage points" & outcome!="ma06_plan_gap"
replace descriptive_units="reported percent" if units=="reported percentage points"
gen str32 ses_label=""
replace ses_label="Higher low-income share" if ses_group==1
replace ses_label="Middle low-income share" if ses_group==2
replace ses_label="Lower low-income share" if ses_group==3
gen str120 summary_note="Unweighted means among reporting schools; N_available is used for plots, not the regression common sample."
gen str100 coverage_note=""
replace coverage_note="No BPS schools in this statewide group; mean is undefined." if n_eligible==0
sort outcome geography ses_group
order outcome outcome_label geography ses_group ses_label n_eligible n_available n_common n_missing ///
    mean sd minimum maximum descriptive_units units population_note
export delimited using "$MA07/07_outcomes_by_ses.csv", nolabel replace
save "`outcomes_groups'", replace
foreach y in ma06_college4_grad att_chronic_abs_20pct {
    local stem "four_year_college"
    local charttitle "Estimated four-year college attendance"
    local popnote "Class of 2025 graduates; college attendance reported in March 2026."
    local measurenote "Approximate rate among graduates, derived from rounded attendance and college-sector percentages."
    if "`y'"=="att_chronic_abs_20pct" {
        local stem "severe_absence"
        local charttitle "Severe chronic absence"
        local popnote "2024-25 students across all grades at each school; not only seniors."
        local measurenote "Severe absence means missing at least 20% of membership days."
    }
    foreach geo in Statewide BPS {
        preserve
        keep if outcome=="`y'" & geography=="`geo'"
        assert _N==3
        assert inrange(mean,0,100) if n_available>0
        sort ses_group
        forvalues g=1/3 {
            local nn`g'=n_available[`g']
        }
        label define ma07_outcome_group 1 "Higher share (N=`nn1')" ///
            2 "Middle share (N=`nn2')" 3 "Lower share (N=`nn3')", replace
        label values ses_group ma07_outcome_group
        graph bar (asis) mean if n_eligible>0, over(ses_group,label(labsize(small))) ///
            bar(1,color(navy)) blabel(bar,format(%4.1f) position(outside) color(navy) size(small)) ///
            yscale(range(0 100)) ylabel(0(20)100,angle(horizontal)) ///
            ytitle("Mean school rate (%)") title("`geo'",size(medsmall)) ///
            xsize(6) ysize(4.5) graphregion(color(white)) name(ma07_`stem'_`geo',replace)
        restore
    }
    graph combine ma07_`stem'_Statewide ma07_`stem'_BPS, cols(2) ycommon iscale(1) ///
        title("`charttitle' across SES groups",size(medsmall)) ///
        subtitle("Fixed statewide student low-income groups; N is schools with a reported outcome",size(small)) ///
        note("Unweighted school means. `popnote'" ///
             "`measurenote'" ///
             "No lower-share BPS group. Middle four: three exam schools and Boston Arts Academy." ///
             "Source: Massachusetts DESE. These outcomes describe different populations.",size(vsmall)) ///
        xsize(12) ysize(6.5) graphregion(color(white)) name(ma07_`stem',replace)
    graph export "$MA07/figures/07_`stem'.png", width(2400) replace
    graph export "$MA07/figures/07_`stem'.svg", replace
}

* 4. Export every existing income-adjusted secondary result, including caveats.
import delimited using "$MA06/06_ses_results.csv", clear varnames(1) asdouble
isid model term
keep if specification=="income_adj" | specification=="BPS_income"
assert _N==65
assert term=="ma_low10"
quietly count if geography=="Statewide" & specification=="income_adj"
assert r(N)==33
quietly count if geography=="BPS" & specification=="BPS_income"
assert r(N)==32
assert ci_low<=b & b<=ci_high & !missing(b,se,ci_low,ci_high,p)
assert inrange(p,0,1) & inrange(p_holm_family,0,1) & inrange(p_holm_global,0,1)
gen str170 adjustment_note="Statewide: campus-tract income, school size/type, English-learner share and disability share; district-clustered uncertainty."
replace adjustment_note="BPS: low-income share plus campus-tract income only; robust uncertainty; not the full statewide control set." if geography=="BPS"
gen str140 campus_income_note="Campus-tract income describes school location, not enrolled students' home neighborhoods; ACS provenance remains unresolved."
gen str130 coefficient_unit="Difference in the outcome's stated units per 10 percentage points higher student low-income share."
sort geography family outcome
export delimited using "$MA07/07_secondary_adjusted_results.csv", nolabel replace

display as result "07 WEBSITE EXPORT COMPLETED: seven PNG/SVG chart pairs and four CSV tables saved."
display as text "Folder: $MA07"
display as text "Figures: 07_Statewide_fafsa_ses3, 07_BPS_fafsa_ses3, 07_fafsa_availability,"
display as text "07_fafsa_adjusted_groups, 07_fafsa_continuous_models, 07_four_year_college, 07_severe_absence."
display as text "Models, SES groups, stage 03/06 results and source files were not overwritten."
display as text "Send 07_website_results.log and the PNGs to verify actual Stata rendering."
log close
