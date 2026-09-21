const { createClient } = require('@supabase/supabase-js');

exports.handler = async () => {
  const names = [
    'SUPABASE_URL',
    'VITE_SUPABASE_URL',
    'SUPABASE_PUBLISHABLE_KEY',
    'SUPABASE_ANON_KEY',
    'VITE_SUPABASE_KEY',
    'SUPABASE_KEY',
  ];

  const values = {};
  for (const n of names) {
    if (process.env[n]) values[n] = process.env[n];
  }

  const url =
    values['SUPABASE_URL'] || values['VITE_SUPABASE_URL'] || null;
  const key =
    values['SUPABASE_PUBLISHABLE_KEY'] ||
    values['SUPABASE_ANON_KEY'] ||
    values['VITE_SUPABASE_KEY'] ||
    values['SUPABASE_KEY'] ||
    null;

  if (!url || !key) {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ db: 'not-configured', vars: Object.keys(values) }),
    };
  }

  try {
    const supabase = createClient(url, key);
    const { error } = await supabase.from('alunos').select('id').limit(1);
    if (error) throw error;
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ db: 'conectado' }),
    };
  } catch (err) {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ db: 'erro: ' + err.message }),
    };
  }
};