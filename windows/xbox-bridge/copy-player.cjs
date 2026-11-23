const fs = require('node:fs');
const path = require('node:path');

const source = require.resolve('xbox-xcloud-player/dist/assets/xCloudPlayer.min.js');
const destination = path.join(__dirname, 'dist', 'player.js');
fs.mkdirSync(path.dirname(destination), { recursive: true });
fs.copyFileSync(source, destination);
fs.copyFileSync(path.join(__dirname, 'player.html'), path.join(__dirname, 'dist', 'player.html'));
fs.cpSync(path.join(__dirname, 'licenses'), path.join(__dirname, 'dist', 'licenses'), { recursive: true });
