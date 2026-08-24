const loanPolicy = require('../src/lib/loanPolicy');

describe('loanPolicy', () => {
  describe('multiplierFor', () => {
    it('returns 3 for Quick/Flexi/Stable loans', () => {
      expect(loanPolicy.multiplierFor('Quick Loan')).toBe(3);
      expect(loanPolicy.multiplierFor('Flexi Loan')).toBe(3);
      expect(loanPolicy.multiplierFor('Stable Loan (12 months)')).toBe(3);
      expect(loanPolicy.multiplierFor('Stable Loan (18 months)')).toBe(3);
    });

    it('returns 4 for Premium Loan and 5 for Maxi Loan', () => {
      expect(loanPolicy.multiplierFor('Premium Loan')).toBe(4);
      expect(loanPolicy.multiplierFor('Maxi Loan')).toBe(5);
    });

    it('falls back to 3 for unknown types', () => {
      expect(loanPolicy.multiplierFor('Some Future Loan')).toBe(3);
      expect(loanPolicy.multiplierFor(undefined)).toBe(3);
    });
  });

  describe('maxLoanAmount', () => {
    it('caps Quick Loan at 3x savings', () => {
      expect(loanPolicy.maxLoanAmount('Quick Loan', 100000)).toBe(300000);
    });

    it('caps Premium Loan at 4x savings', () => {
      expect(loanPolicy.maxLoanAmount('Premium Loan', 100000)).toBe(400000);
    });

    it('caps Maxi Loan at 5x savings', () => {
      expect(loanPolicy.maxLoanAmount('Maxi Loan', 100000)).toBe(500000);
    });

    it('returns 0 when the member has no savings', () => {
      expect(loanPolicy.maxLoanAmount('Maxi Loan', 0)).toBe(0);
      expect(loanPolicy.maxLoanAmount('Quick Loan', null)).toBe(0);
    });
  });

  describe('status sets', () => {
    it('blocks new applications for overdue, defaulted and in_recovery loans', () => {
      expect(loanPolicy.DEFAULT_BLOCKING_STATUSES).toEqual(
        expect.arrayContaining(['overdue', 'defaulted', 'in_recovery']),
      );
    });

    it('counts approved/active/repaying/overdue/in_recovery as active for the reduction guard', () => {
      expect(loanPolicy.ACTIVE_LOAN_STATUSES).toEqual(
        expect.arrayContaining(['approved', 'active', 'repaying', 'overdue', 'in_recovery']),
      );
      expect(loanPolicy.ACTIVE_LOAN_STATUSES).not.toContain('completed');
      expect(loanPolicy.ACTIVE_LOAN_STATUSES).not.toContain('rejected');
    });
  });
});
