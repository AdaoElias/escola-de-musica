const { createClient } = require('@supabase/supabase-js');

exports.handler = async () => {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;

  if (!url || !key) {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ db: 'not-configured' }),
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