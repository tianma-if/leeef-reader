import assert from 'node:assert/strict'
import { readFileSync, writeFileSync, statSync, existsSync } from 'node:fs'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash, createPublicKey, verify } from 'node:crypto'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const updaterPublicKey = () => JSON.parse(readFileSync(join(appRoot, 'src-tauri/tauri.conf.json'))).plugins.updater.pubkey

// Tauri wraps Minisign public keys and signatures in an outer base64 layer.
// Verify the payload and trusted comment, including the fixed client key ID.
export function verifyUpdaterSignature(payload, signature, publicKey) {
  const keyText = Buffer.from(publicKey, 'base64').toString('utf8').trim().split(/\r?\n/)
  const sigText = Buffer.from(signature, 'base64').toString('utf8').trim().split(/\r?\n/)
  assert.equal(keyText.length, 2, 'Malformed updater public key')
  assert.equal(sigText.length, 4, 'Malformed updater signature')
  const key = Buffer.from(keyText[1], 'base64')
  const packet = Buffer.from(sigText[1], 'base64')
  const globalSignature = Buffer.from(sigText[3], 'base64')
  assert.equal(key.length, 42)
  assert.equal(packet.length, 74)
  assert.equal(globalSignature.length, 64)
  assert.equal(key.subarray(0, 2).toString(), 'Ed')
  assert.deepEqual(packet.subarray(2, 10), key.subarray(2, 10), 'Updater signing key does not match client public key')
  assert(sigText[2].startsWith('trusted comment: '))
  const algorithm = packet.subarray(0, 2).toString()
  assert(['Ed', 'ED'].includes(algorithm), 'Unsupported updater signature algorithm')
  const message = algorithm === 'ED' ? createHash('blake2b512').update(payload).digest() : payload
  const edKey = createPublicKey({
    key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), key.subarray(10)]),
    format: 'der', type: 'spki',
  })
  const detached = packet.subarray(10)
  assert(verify(null, message, edKey, detached), 'Updater payload signature is invalid')
  assert(verify(null, Buffer.concat([detached, Buffer.from(sigText[2].slice(17))]), edKey, globalSignature), 'Updater trusted comment signature is invalid')
}

export function releaseVersion(tag, root = appRoot) {
  const version = JSON.parse(readFileSync(join(root, 'package.json'))).version
  assert.match(version, /^\d+\.\d+\.\d+$/)
  assert.equal(tag, `v${version}`, 'Release tag must match package.json')
  assert.equal(JSON.parse(readFileSync(join(root, 'src-tauri/tauri.conf.json'))).version, version)
  const cargo = readFileSync(join(root, 'src-tauri/Cargo.toml'), 'utf8')
  assert.equal(cargo.match(/^version = "([^"]+)"/m)?.[1], version)
  return version
}

// Build from the assets actually attached to this release. This also preserves
// the other desktop platform when only one platform is rebuilt in a Draft.
export function manifestForAssets({ directory, version, tag, repository, notes, required = 'all', publicKey = updaterPublicKey() }) {
  assert.equal(tag, `v${version}`)
  assert.match(repository, /^[\w.-]+\/[\w.-]+$/)
  assert(['all', 'macos', 'windows'].includes(required))
  const platforms = {}
  const nonempty = (name) => {
    assert(statSync(join(directory, name)).size > 0, `Empty asset: ${name}`)
  }
  const asset = (name) => {
    nonempty(name)
    nonempty(`${name}.sig`)
    const signature = readFileSync(join(directory, `${name}.sig`), 'utf8').trim()
    assert(signature.length > 0)
    verifyUpdaterSignature(readFileSync(join(directory, name)), signature, publicKey)
    return { url: `https://github.com/${repository}/releases/download/${tag}/${name}`, signature }
  }
  const mac = `Leeef-Reader-${version}-macos-universal`
  const win = `Leeef-Reader-${version}-windows-x64-setup.exe`
  const hasMac = [`.dmg`, `.zip`, `.app.tar.gz`, `.app.tar.gz.sig`].some(ext => existsSync(join(directory, mac + ext)))
  const hasWin = [win, `${win}.sig`].some(name => existsSync(join(directory, name)))
  if (required !== 'windows' || hasMac) {
    nonempty(`${mac}.dmg`)
    nonempty(`${mac}.zip`)
    platforms['darwin-aarch64'] = platforms['darwin-x86_64'] = asset(`${mac}.app.tar.gz`)
  }
  if (required !== 'macos' || hasWin) {
    platforms['windows-x86_64'] = asset(win)
    const checksum = readFileSync(join(directory, 'SHA256SUMS-windows.txt'), 'utf8').trim()
    const hash = createHash('sha256').update(readFileSync(join(directory, win))).digest('hex')
    assert.equal(checksum, `${hash}  ${win}`, 'Windows SHA-256 manifest does not match the installer')
  }
  return { version, notes, pub_date: new Date().toISOString(), platforms }
}

export function auditManifest(actual, expected) {
  assert.equal(actual.version, expected.version)
  assert.deepEqual(actual.platforms, expected.platforms, 'Updater URLs and signatures must match release assets')
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, directory, required = 'all'] = process.argv.slice(2)
  const version = releaseVersion(process.env.RELEASE_TAG)
  if (command === 'preflight') {
    const release = JSON.parse(readFileSync(directory, 'utf8'))
    assert.equal(release.tag_name, process.env.RELEASE_TAG)
    assert.equal(release.name, process.env.RELEASE_TAG, 'Release title must be vX.Y.Z')
    if (required !== 'appstore-submit') {
      assert.equal(release.draft, true, 'Builds may only upload to a Draft Release')
    }
    assert.equal(release.prerelease, false)
    console.log(`Validated Draft ${release.tag_name}`)
  } else {
    assert(['generate', 'audit'].includes(command))
    const manifest = manifestForAssets({
      directory, version, tag: process.env.RELEASE_TAG,
      repository: process.env.GITHUB_REPOSITORY,
      notes: process.env.RELEASE_NOTES ?? '', required,
    })
    const target = join(directory, 'latest.json')
    if (command === 'generate') writeFileSync(target, `${JSON.stringify(manifest, null, 2)}\n`)
    else auditManifest(JSON.parse(readFileSync(target, 'utf8')), manifest)
    console.log(`${command}: ${Object.keys(manifest.platforms).join(', ')}`)
  }
}
