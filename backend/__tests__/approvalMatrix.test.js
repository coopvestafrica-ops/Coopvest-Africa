const { maxApprovableAmount, SUPER_ADMIN_ROLES } = require('../src/lib/approvalMatrix');

const thresholds = {
  levels: [
    { level: 1, maxAmount: 100000, role: 'staff' },
    { level: 2, maxAmount: 1000000, role: 'admin' },
    { level: 3, maxAmount: null, role: 'super_admin' }, // unlimited
  ],
};

describe('approvalMatrix.maxApprovableAmount', () => {
  it('staff are capped at their level max', () => {
    expect(maxApprovableAmount('staff', thresholds)).toBe(100000);
  });

  it('admins are capped at their level max', () => {
    expect(maxApprovableAmount('admin', thresholds)).toBe(1000000);
  });

  it('super admin roles are always unlimited', () => {
    SUPER_ADMIN_ROLES.forEach((role) => {
      expect(maxApprovableAmount(role, thresholds)).toBe(Infinity);
    });
  });

  it('values above the unlimited sentinel are treated as unlimited', () => {
    expect(maxApprovableAmount('admin', { levels: [{ maxAmount: 2e12, role: 'admin' }] })).toBe(Infinity);
  });

  it('unknown roles get zero (can never approve outright)', () => {
    expect(maxApprovableAmount('member', thresholds)).toBe(0);
    expect(maxApprovableAmount(undefined, thresholds)).toBe(0);
  });

  it('takes the highest matching level when a role appears more than once', () => {
    const dup = { levels: [{ maxAmount: 50000, role: 'staff' }, { maxAmount: 75000, role: 'staff' }] };
    expect(maxApprovableAmount('staff', dup)).toBe(75000);
  });
});
