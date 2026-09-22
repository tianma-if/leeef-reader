import { expect, it } from 'vitest'
import { importBatch } from './importBatch'

it('continues after a damaged book and keeps only failed files for retry', async () => {
  const visited: string[] = []
  const progress: number[] = []
  const result = await importBatch(['first.epub', 'bad.epub', 'last.epub'], async (file) => {
    visited.push(file)
    if (file === 'bad.epub') throw new Error('损坏的文件')
  }, (count) => progress.push(count))
  expect(visited).toEqual(['first.epub', 'bad.epub', 'last.epub'])
  expect(progress).toEqual([1, 2, 3])
  expect(result).toEqual({ succeeded: 2, failures: [{ item: 'bad.epub', error: '损坏的文件' }] })
})
