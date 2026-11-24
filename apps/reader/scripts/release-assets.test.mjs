import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { generateKeyPairSync, randomBytes, sign, createHash } from 'node:crypto'
import { manifestForAssets, auditManifest, verifyUpdaterSignature } from './release-assets.mjs'

const { privateKey, publicKey } = generateKeyPairSync('ed25519')
const keyId = randomBytes(8)
const publicPacket = Buffer.concat([Buffer.from('Ed'), keyId, publicKey.export({ type: 'spki', format: 'der' }).subarray(-32)])
const encodedPublicKey = Buffer.from(`untrusted comment: test key\n${publicPacket.toString('base64')}\n`).toString('base64')
function signed(payload) {
  const detached = sign(null, createHash('blake2b512').update(payload).digest(), privateKey)
  const packet = Buffer.concat([Buffer.from('ED'), keyId, detached])
  const comment = 'test asset'
  const global = sign(null, Buffer.concat([detached, Buffer.from(comment)]), privateKey)
  return Buffer.from(`untrusted comment: test signature\n${packet.toString('base64')}\ntrusted comment: ${comment}\n${global.toString('base64')}\n`).toString('base64')
}
function fixture(t, names) {
  const directory = mkdtempSync(join(tmpdir(), 'leeef-assets-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  for (const name of names) {
    writeFileSync(join(directory, name), name.endsWith('.sig') ? signed(Buffer.from(`asset-${name.slice(0, -4)}`)) : `asset-${name}`)
  }
  const exe = names.find(name => name.endsWith('windows-x64-setup.exe'))
  if (exe) {
    const hash = createHash('sha256').update(readFileSync(join(directory, exe))).digest('hex')
    writeFileSync(join(directory, 'SHA256SUMS-windows.txt'), `${hash}  ${exe}\n`)
  }
  return { directory, publicKey: encodedPublicKey, version: '2.7.0', tag: 'v2.7.0', repository: 'tianma-if/leeef-reader', notes: '主要更新\nKey Changes' }
}
const mac = ['.dmg', '.zip', '.app.tar.gz', '.app.tar.gz.sig'].map(ext => `Leeef-Reader-2.7.0-macos-universal${ext}`)
const win = ['.exe', '.exe.sig'].map(ext => `Leeef-Reader-2.7.0-windows-x64-setup${ext}`)

test('combined manifest keeps both Mac architectures and Windows', t => {
  const manifest = manifestForAssets(fixture(t, [...mac, ...win]))
  assert.deepEqual(Object.keys(manifest.platforms).sort(), ['darwin-aarch64', 'darwin-x86_64', 'windows-x86_64'])
  assert.deepEqual(manifest.platforms['darwin-aarch64'], manifest.platforms['darwin-x86_64'])
  assert.match(manifest.platforms['windows-x86_64'].url, /\/v2\.7\.0\/Leeef-Reader-2\.7\.0-windows-x64-setup\.exe$/)
  assert(manifest.platforms['windows-x86_64'].signature.length > 0)
  auditManifest(structuredClone(manifest), manifest)
})

test('single platform retry preserves other platform entries', t => {
  const options = fixture(t, [...mac, ...win])
  for (const required of ['macos', 'windows']) {
    assert.equal(Object.keys(manifestForAssets({ ...options, required }).platforms).length, 3)
  }
})

test('all requires Windows, and partial Windows assets fail even on a macOS retry', t => {
  const options = fixture(t, mac)
  assert.throws(() => manifestForAssets(options))
  assert.equal(Object.keys(manifestForAssets({ ...options, required: 'macos' }).platforms).length, 2)
  writeFileSync(join(options.directory, win[0]), 'installer')
  assert.throws(() => manifestForAssets({ ...options, required: 'macos' }))
})

test('Windows-only Draft can be prepared without declaring macOS', t => {
  const options = fixture(t, win)
  assert.deepEqual(Object.keys(manifestForAssets({ ...options, required: 'windows' }).platforms), ['windows-x86_64'])
})

test('rejects empty installer, mismatched version, URL or signature, and dropped platform', t => {
  const options = fixture(t, [...mac, ...win])
  const expected = manifestForAssets(options)
  for (const field of ['url', 'signature']) {
    const actual = structuredClone(expected)
    actual.platforms['windows-x86_64'][field] = 'incorrect'
    assert.throws(() => auditManifest(actual, expected))
  }
  const dropped = structuredClone(expected)
  delete dropped.platforms['darwin-aarch64']
  assert.throws(() => auditManifest(dropped, expected))
  assert.throws(() => auditManifest({ ...expected, version: '2.6.0' }, expected))
  assert.throws(() => manifestForAssets({ ...options, tag: 'v2.6.0' }))
  const checksumPath = join(options.directory, 'SHA256SUMS-windows.txt')
  writeFileSync(checksumPath, `deadbeef  ${win[0]}\n`)
  assert.throws(() => manifestForAssets(options))
  const hash = createHash('sha256').update(readFileSync(join(options.directory, win[0]))).digest('hex')
  writeFileSync(checksumPath, `${hash}  ${win[0]}\n`)
  writeFileSync(join(options.directory, win[0]), '')
  assert.throws(() => manifestForAssets(options))
})


test('updater verification rejects tampered payloads, comments and a different client key', () => {
  const payload = Buffer.from('installer')
  const signature = signed(payload)
  verifyUpdaterSignature(payload, signature, encodedPublicKey)
  assert.throws(() => verifyUpdaterSignature(Buffer.from('modified'), signature, encodedPublicKey))
  const commentTampered = Buffer.from(Buffer.from(signature, 'base64').toString().replace('trusted comment: test asset', 'trusted comment: changed')).toString('base64')
  assert.throws(() => verifyUpdaterSignature(payload, commentTampered, encodedPublicKey))
  const differentPacket = Buffer.from(publicPacket)
  differentPacket[2] ^= 1
  const differentKey = Buffer.from(`untrusted comment: different\n${differentPacket.toString('base64')}`).toString('base64')
  assert.throws(() => verifyUpdaterSignature(payload, signature, differentKey))
})

test('preflight validates versions, Draft state and release title', t => {
  const options = fixture(t, [])
  const releasePath = join(options.directory, 'release.json')
  const script = new URL('./release-assets.mjs', import.meta.url)
  const appVersion = JSON.parse(readFileSync(new URL('../package.json', import.meta.url))).version
  const tag = `v${appVersion}`
  const run = (release, platform = 'all', releaseTag = tag) => {
    writeFileSync(releasePath, JSON.stringify(release))
    return spawnSync(process.execPath, [fileURLToPath(script), 'preflight', releasePath, platform], {
      env: { ...process.env, RELEASE_TAG: releaseTag }, encoding: 'utf8',
    }).status
  }
  const draft = { tag_name: tag, name: tag, draft: true, prerelease: false }
  assert.equal(run(draft), 0)
  assert.notEqual(run({ ...draft, draft: false }), 0)
  assert.notEqual(run({ ...draft, prerelease: true }), 0)
  assert.notEqual(run({ ...draft, name: 'informal title' }), 0)
  assert.notEqual(run(draft, 'all', 'v0.0.0'), 0)
  assert.equal(run({ ...draft, draft: false }, 'appstore-submit'), 0)
})
