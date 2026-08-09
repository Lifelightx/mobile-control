const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');
const { execSync } = require('child_process');

// IMPORTANT: Replace this with your actual GitHub repo URL where releases are published
const GITHUB_REPO = process.env.DEVCONTROL_REPO || 'Lifelightx/mobile-control';
const VERSION = process.env.DEVCONTROL_VERSION || require('../package.json').version;

async function downloadBinary() {
  const platform = os.platform();
  const arch = os.arch();

  if (platform !== 'linux') {
    console.warn('[DevControl] The input daemon is only supported on Linux.');
    return;
  }

  let target;
  if (arch === 'x64') {
    target = 'x86_64-unknown-linux-gnu';
  } else if (arch === 'arm64') {
    target = 'aarch64-unknown-linux-gnu';
  } else {
    console.error(`[DevControl] Unsupported architecture: ${arch}`);
    process.exit(1);
  }

  const binaryName = `devcontrol-input-${target}`;
  // Adjust this URL based on how GitHub Actions structures the release assets
  const url = `https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${binaryName}`;
  const binDir = path.join(__dirname, '..', 'bin');
  const dest = path.join(binDir, 'devcontrol-input');

  if (!fs.existsSync(binDir)) {
    fs.mkdirSync(binDir, { recursive: true });
  }

  console.log(`[DevControl] Downloading prebuilt daemon for ${target}...`);
  console.log(`[DevControl] URL: ${url}`);

  if (!GITHUB_REPO || GITHUB_REPO === 'YOUR_ORG/YOUR_REPO') {
    console.warn(`[DevControl] GITHUB_REPO placeholder detected. Falling back to local compilation...`);
    try {
      console.log(`[DevControl] Compiling Rust daemon from source...`);
      execSync('cd ../rust && cargo build --release', { stdio: 'inherit' });
      const compiledPath = path.join(__dirname, '../../rust/target/release/devcontrol-input');
      fs.copyFileSync(compiledPath, dest);
      console.log(`[DevControl] Successfully compiled locally.`);
    } catch (e) {
      console.error(`[DevControl] Failed to compile Rust daemon. Make sure you have Rust installed.`);
    }
    return;
  }

  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        return https.get(res.headers.location, (redirectRes) => {
          pipeToFile(redirectRes, dest, resolve, reject);
        }).on('error', reject);
      }
      
      if (res.statusCode !== 200) {
        reject(new Error(`Failed to download binary: HTTP ${res.statusCode}`));
        return;
      }
      
      pipeToFile(res, dest, resolve, reject);
    }).on('error', reject);
  });
}

function pipeToFile(res, dest, resolve, reject) {
  const file = fs.createWriteStream(dest);
  res.pipe(file);
  file.on('finish', () => {
    file.close();
    fs.chmodSync(dest, 0o755);
    console.log('[DevControl] Daemon downloaded successfully.');
    resolve();
  });
  file.on('error', (err) => {
    fs.unlink(dest, () => {});
    reject(err);
  });
}

downloadBinary().catch((err) => {
  console.error('[DevControl] Error during postinstall:', err.message);
  process.exit(1);
});
