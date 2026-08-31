/**
 * Registration data merge helpers.
 *
 * The mobile app's complete-registration step may re-submit an earlier-saved
 * payload that omits fields the member already completed. To avoid falsely
 * reporting persisted data as missing, validation merges the request body
 * over the existing KYC row: body fields win when they carry a value,
 * previously saved values fill the gaps.
 */

function hasValue(v) {
  return v !== null && v !== undefined && String(v).trim() !== '';
}

function pickPresent(obj) {
  return Object.fromEntries(Object.entries(obj).filter(([, v]) => hasValue(v)));
}

/**
 * Build the candidate objects used for completeness validation by merging
 * request body fields over the existing KYC row.
 */
function buildRegistrationCandidates(body, existingKyc) {
  const personalBody = {
    gender: body.gender,
    address: body.address,
    state: body.state,
    lga: body.lga,
    staff_id: body.staff_id,
    id_type: body.id_type,
    nok_name: body.nok_name,
    nok_relationship: body.nok_relationship,
    nok_phone: body.nok_phone,
    nok_address: body.nok_address,
    monthly_amount: body.monthly_amount,
    contribution_method: body.contribution_method,
    preferred_payment_day: body.preferred_payment_day,
  };
  const employmentBody = {
    occupation: body.occupation,
    employer_name: body.employer_name,
    employment_type: body.employment_type,
    employer_staff_id: body.employer_staff_id,
    work_address: body.work_address,
    years_of_employment: body.years_of_employment,
  };

  const personal_info = {
    ...(existingKyc?.personal_info || {}),
    ...pickPresent(personalBody),
    // date_of_birth and address are both top-level kyc columns and
    // (historically) inside personal_info; accept either persisted location
    // when the body omits them.
    date_of_birth: hasValue(body.date_of_birth)
      ? body.date_of_birth
      : (existingKyc?.date_of_birth || existingKyc?.personal_info?.date_of_birth),
    address: hasValue(body.address)
      ? body.address
      : (existingKyc?.address || existingKyc?.personal_info?.address),
  };

  const employment_info = {
    ...(existingKyc?.employment_info || {}),
    ...pickPresent(employmentBody),
  };

  return { personal_info, employment_info };
}

/**
 * Merge a stored personal_info object with the top-level date_of_birth
 * column, for the status/completeness read endpoints.
 */
function mergeStoredPersonalInfo(kycRow) {
  if (!kycRow) return {};
  return {
    ...(kycRow.personal_info || {}),
    date_of_birth: kycRow.personal_info?.date_of_birth || kycRow.date_of_birth,
    address: kycRow.personal_info?.address || kycRow.address,
  };
}


const MIN_AGE_YEARS = 18;

/**
 * Exact age in full years (calendar-aware, handles leap years and birthdays
 * later in the year). Accepts YYYY-MM-DD or DD/MM/YYYY; returns null when the
 * date cannot be parsed, so callers can reject unparseable input explicitly.
 */
function ageInYears(dob, now = new Date()) {
  if (!hasValue(dob)) return null;
  let d;
  const s = String(dob).trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  if (m) {
    d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  } else {
    m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(s);
    if (!m) return null;
    d = new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]));
  }
  if (Number.isNaN(d.getTime())) return null;
  let age = now.getFullYear() - d.getFullYear();
  const monthDiff = now.getMonth() - d.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < d.getDate())) age -= 1;
  return age;
}

function isAdult(dob, now = new Date()) {
  const age = ageInYears(dob, now);
  return age !== null && age >= MIN_AGE_YEARS;
}

module.exports = { hasValue, buildRegistrationCandidates, mergeStoredPersonalInfo, ageInYears, isAdult, MIN_AGE_YEARS };
