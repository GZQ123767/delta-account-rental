window.DELTA_SUPABASE = {
  url: 'https://gbmpipwtpgqufskhysrb.supabase.co',
  key: 'sb_publishable_DpVGiD9tQDEf1bYZCehNPQ_jU22-_UR'
};
window.addEventListener('DOMContentLoaded', () => {
  const operations = document.createElement('script');
  operations.src = 'operations.js';
  operations.onload = () => {
    const payments = document.createElement('script');
    payments.src = 'payments.js';
    document.body.appendChild(payments);
  };
  document.body.appendChild(operations);
});
