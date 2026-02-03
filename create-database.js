const { Client } = require('pg');

async function createDatabase() {
  const client = new Client({
    host: process.env.DB_HOST || 'bia.c4tu4ke4glen.us-east-1.rds.amazonaws.com',
    port: process.env.DB_PORT || 5432,
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PWD || 'lPKRS3iLiGlzKS4Wh9zJ',
    database: 'postgres', // Conecta ao banco padrão
    ssl: {
      require: true,
      rejectUnauthorized: false,
    }
  });

  try {
    await client.connect();
    console.log('Conectado ao PostgreSQL');
    
    // Verifica se o banco 'bia' já existe
    const result = await client.query("SELECT 1 FROM pg_database WHERE datname = 'bia'");
    
    if (result.rows.length === 0) {
      // Cria o banco 'bia'
      await client.query('CREATE DATABASE bia');
      console.log('Banco de dados "bia" criado com sucesso!');
    } else {
      console.log('Banco de dados "bia" já existe.');
    }
    
  } catch (error) {
    console.error('Erro:', error.message);
  } finally {
    await client.end();
  }
}

createDatabase();
