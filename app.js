const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const version = process.env.VERSION || 'unknown';

app.get('/', (req, res) => {
  res.send('Hello World from Nodejs + Docker!!');
});

// Health check
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Version check
app.get('/version', (req, res) => {
  res.status(200).send(`The deployed version is: ${version}`);
});

app.listen(port, () => {
  console.log(`App listening at http://localhost:${port}`);
});
