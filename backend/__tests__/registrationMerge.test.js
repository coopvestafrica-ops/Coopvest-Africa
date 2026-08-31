const {
  hasValue,
  buildRegistrationCandidates,
  mergeStoredPersonalInfo,
  ageInYears,
  isAdult,
} = require('../src/services/registrationMerge');

const fullBody = {
  gender: 'Male',
  date_of_birth: '1990-01-15',
  address: '12 Test Street',
  state: 'Lagos',
  lga: 'Ikeja',
  id_type: 'NIN',
  staff_id: 'QA/001',
  occupation: 'Engineer',
  employer_name: 'QA Corp',
  employment_type: 'Full-time Employee',
  employer_staff_id: 'QA/001',
  work_address: '1 QA Road',
  years_of_employment: '1 - 5 years',
  monthly_amount: '10000',
  contribution_method: 'manual',
  preferred_payment_day: '28',
  nok_name: 'QA Kin',
  nok_relationship: 'Sibling',
  nok_phone: '+2348000000000',
  nok_address: '12 Test Street',
};

describe('hasValue', () => {
  test('treats null, undefined, and blank strings as missing', () => {
    expect(hasValue(null)).toBe(false);
    expect(hasValue(undefined)).toBe(false);
    expect(hasValue('')).toBe(false);
    expect(hasValue('   ')).toBe(false);
  });

  test('treats real values (including 0) as present', () => {
    expect(hasValue('x')).toBe(true);
    expect(hasValue(0)).toBe(true);
    expect(hasValue(5000)).toBe(true);
  });
});

describe('buildRegistrationCandidates', () => {
  test('full body without an existing KYC row passes all fields through', () => {
    const { personal_info, employment_info } = buildRegistrationCandidates(fullBody, null);
    expect(personal_info.gender).toBe('Male');
    expect(personal_info.date_of_birth).toBe('1990-01-15');
    expect(personal_info.state).toBe('Lagos');
    expect(personal_info.monthly_amount).toBe('10000');
    expect(personal_info.nok_name).toBe('QA Kin');
    expect(employment_info.occupation).toBe('Engineer');
    expect(employment_info.employer_name).toBe('QA Corp');
    expect(employment_info.employment_type).toBe('Full-time Employee');
  });

  test('body fields win over previously saved values', () => {
    const existing = {
      date_of_birth: '1980-05-05',
      personal_info: { gender: 'Female', state: 'Oyo', nok_name: 'Old Kin' },
      employment_info: { occupation: 'Teacher', employer_name: 'Old School' },
    };
    const { personal_info, employment_info } = buildRegistrationCandidates(fullBody, existing);
    expect(personal_info.gender).toBe('Male');
    expect(personal_info.date_of_birth).toBe('1990-01-15');
    expect(personal_info.state).toBe('Lagos');
    expect(employment_info.employer_name).toBe('QA Corp');
  });

  test('existing KYC data fills fields the body omits', () => {
    const existing = {
      date_of_birth: '1989-07-07',
      personal_info: { gender: 'Male', state: 'Oyo', monthly_amount: '5000', nok_name: 'Kin', nok_relationship: 'Spouse', nok_phone: '+234' },
      employment_info: { occupation: 'Civil Servant', employer_name: 'Bowen', employment_type: 'Full-time Employee' },
    };
    const body = { address: 'New Address', monthly_amount: '8000' };
    const { personal_info, employment_info } = buildRegistrationCandidates(body, existing);
    expect(personal_info.date_of_birth).toBe('1989-07-07');
    expect(personal_info.gender).toBe('Male');
    expect(personal_info.state).toBe('Oyo');
    expect(personal_info.address).toBe('New Address');
    expect(personal_info.monthly_amount).toBe('8000');
    expect(employment_info.occupation).toBe('Civil Servant');
    expect(employment_info.employment_type).toBe('Full-time Employee');
  });

  test('blank body values do not overwrite saved values', () => {
    const existing = { personal_info: { gender: 'Male' }, employment_info: { occupation: 'Engineer' } };
    const { personal_info, employment_info } = buildRegistrationCandidates(
      { gender: '   ', occupation: '' },
      existing
    );
    expect(personal_info.gender).toBe('Male');
    expect(employment_info.occupation).toBe('Engineer');
  });

  test('falls back to date_of_birth stored inside personal_info', () => {
    const existing = { personal_info: { date_of_birth: '1992-02-02' } };
    const { personal_info } = buildRegistrationCandidates({}, existing);
    expect(personal_info.date_of_birth).toBe('1992-02-02');
  });
});

describe('mergeStoredPersonalInfo', () => {
  test('merges the top-level date_of_birth column into personal_info', () => {
    const row = { date_of_birth: '1989-07-07', personal_info: { gender: 'Male' } };
    const merged = mergeStoredPersonalInfo(row);
    expect(merged.date_of_birth).toBe('1989-07-07');
    expect(merged.gender).toBe('Male');
  });

  test('personal_info date_of_birth takes precedence when present', () => {
    const row = { date_of_birth: '1989-07-07', personal_info: { date_of_birth: '2000-01-01' } };
    expect(mergeStoredPersonalInfo(row).date_of_birth).toBe('2000-01-01');
  });

  test('returns empty object for a missing KYC row', () => {
    expect(mergeStoredPersonalInfo(null)).toEqual({});
  });
});

describe('ageInYears / isAdult', () => {
  // Fixed "today" so the tests never drift with the calendar.
  const now = new Date(2026, 7, 30); // 2026-08-30

  test('parses YYYY-MM-DD and DD/MM/YYYY', () => {
    expect(ageInYears('1990-01-15', now)).toBe(36);
    expect(ageInYears('15/01/1990', now)).toBe(36);
  });

  test('exact 18th birthday counts as an adult', () => {
    expect(ageInYears('2008-08-30', now)).toBe(18);
    expect(isAdult('2008-08-30', now)).toBe(true);
  });

  test('birthday tomorrow is still 17', () => {
    expect(ageInYears('2008-08-31', now)).toBe(17);
    expect(isAdult('2008-08-31', now)).toBe(false);
  });

  test('clear minors and clear adults', () => {
    expect(isAdult('2015-06-01', now)).toBe(false);
    expect(isAdult('1985-03-10', now)).toBe(true);
  });

  test('leap-day birthdays age correctly', () => {
    expect(ageInYears('2000-02-29', now)).toBe(26);
    expect(isAdult('2000-02-29', now)).toBe(true);
  });

  test('unparseable or missing dates return null', () => {
    expect(ageInYears('not-a-date', now)).toBeNull();
    expect(ageInYears('', now)).toBeNull();
    expect(ageInYears(null, now)).toBeNull();
    expect(isAdult('not-a-date', now)).toBe(false);
  });
});
