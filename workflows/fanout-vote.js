export const meta = {
  name: 'fanout-vote',
  description: 'Fan out a requirement to N heads-down crews in isolated worktrees, peer-review + neutral panel judge, re-polish by stealing others\' strengths, pick the winner',
  whenToUse: 'One requirement, want a sampled/best-of-N answer where crews learn from each other before a neutral verdict',
  phases: [
    { title: 'Setup' },       // quartermaster mints group + named worktrees
    { title: 'Draft' },       // heads-down fan-out
    { title: 'Peer' },        // crew learn from each other
    { title: 'Panel' },       // neutral multi-lens reviewers vote the verdict
    { title: 'Polish' },      // re-polish in place, stealing strengths
  ],
}

// ---- inputs ---------------------------------------------------------------
// args: { req: string, crewSize?: number, maxRounds?: number, draftRoot?: string }
const _args     = typeof args === 'string' ? JSON.parse(args) : (args ?? {})
const req       = _args.req
const N         = _args.crewSize  ?? 4
const maxRounds = _args.maxRounds ?? 2          // re-polish rounds (1-2; guards mode collapse)
const root      = _args.draftRoot ?? 'drafts'
if (!req) throw new Error('args.req (the requirement) is required')

// ---- schemas --------------------------------------------------------------
const MANIFEST = {
  type: 'object', required: ['group', 'crew'],
  properties: {
    group: { type: 'string' },                 // requirement-derived slug, e.g. "add-oauth-login"
    crew: { type: 'array', items: {
      type: 'object', required: ['name', 'dir', 'branch'],
      properties: { name: {type:'string'}, dir: {type:'string'}, branch: {type:'string'} },
    }},
  },
}
const PEER = {                                  // one crew's takeaways after reading everyone
  type: 'object', required: ['steal'],
  properties: { steal: { type: 'string' } },   // concrete ideas THIS crew will adopt
}
const VERDICT = {                               // one neutral reviewer, one lens
  type: 'object', required: ['lens', 'ranking'],
  properties: {
    lens: { type: 'string' },
    ranking: { type: 'array', items: {          // best -> worst
      type: 'object', required: ['name', 'reason'],
      properties: { name:{type:'string'}, reason:{type:'string'} },
    }},
  },
}
const LENSES = ['correctness', 'matches-intent', 'maintainability']

// ---- Setup: quartermaster owns all worktree lifecycle ---------------------
phase('Setup')
const plan = await agent(
  `You are the quartermaster for a best-of-${N} coding round.\n`
  + `REQUIREMENT (name the group after THIS):\n${req}\n\n`
  + `Derive a short kebab-case group name that summarizes the requirement `
  + `(e.g. "add-oauth-login", "fix-csv-parser") — 2-4 words.\n`
  + `Claim it atomically: mkdir ${root}/<name>; if it already exists, append -2, -3, ... `
  + `and retry, so a concurrent or repeat run can't collide.\n`
  + `Then create ${N} worktrees, each on its own branch:\n`
  + `  git worktree add ${root}/<name>/<crew> -b <name>-<crew>\n`
  + `Give crew readable code-names (falcon, otter, lynx, heron, ...).\n`
  + `Do NOT remove anything. Return group(the final name) + a list of {name, dir(abs), branch}.`,
  { phase: 'Setup', label: 'quartermaster', schema: MANIFEST })

const crew = plan.crew
const byName = Object.fromEntries(crew.map(m => [m.name, m]))
const dirList = crew.map(c => `${c.name}=${c.dir}`).join(', ')
log(`group ${plan.group}: ${crew.map(m => m.name).join(', ')}`)

// ---- Draft: heads-down fan-out --------------------------------------------
phase('Draft')
await parallel(crew.map(m => () =>
  agent(
    `You are "${m.name}". Your worktree: ${m.dir}\n\n`
    + `REQUIREMENT:\n${req}\n\n`
    + `Work heads-down: guess the user's intent yourself, make your own decisions, `
    + `implement a complete solution in your worktree. Do NOT ask questions. `
    + `When done, git add -A && git commit -m "${m.name}: draft" (snapshot for review).`,
    { phase: 'Draft', label: m.name })))

// ---- Peer + Panel + Polish loop: judge -> feedback -> revise, until plateau
let prevTop = null
for (let round = 1; round <= maxRounds; round++) {

  // Peer: crew read every worktree and note what they'll adopt from each other
  const peer = (await parallel(crew.map(m => () =>
    agent(
      `You are "${m.name}". Your dir: ${m.dir}\nAll crew dirs: ${dirList}\n\n`
      + `cd into EACH worktree, read the code and 'git diff main'. List concretely `
      + `what YOU will steal from the others to improve your own solution.`,
      { phase: 'Peer', label: `peer:${m.name}`, schema: PEER })
      .then(r => r && ({ name: m.name, ...r }))))).filter(Boolean)

  // Panel: neutral reviewers, one lens each, own the verdict
  const verdicts = (await parallel(LENSES.map(lens => () =>
    agent(
      `You are a NEUTRAL reviewer, not competing. Lens: ${lens}.\nCrew dirs: ${dirList}\n\n`
      + `Read every worktree + 'git diff main'. Rank the crew best->worst on your `
      + `lens only, with a one-line reason each. Be strict and specific.`,
      { phase: 'Panel', label: `panel:${lens}`, schema: VERDICT })))).filter(Boolean)

  // consensus: Borda count across the lens rankings
  const score = {}
  for (const v of verdicts)
    v.ranking.forEach((r, i) => { score[r.name] = (score[r.name] ?? 0) + (crew.length - i) })
  const board = crew.map(m => m.name).sort((a, b) => (score[b] ?? 0) - (score[a] ?? 0))
  const top = board[0]
  log(`round ${round} verdict: ${board.join(' > ')}  (leader: ${top})`)

  // stop when the leader stops changing (plateau) or rounds are exhausted
  if (top === prevTop || round === maxRounds) {
    return {
      group: plan.group, winner: top, leaderboard: board,
      dirs: byName, note: 'worktrees kept for inspection',
    }
  }
  prevTop = top

  // Polish: revise IN PLACE — adopt what's better, keep your identity
  const stealFor = name => {
    const mine = peer.find(p => p.name === name)
    const praise = verdicts.flatMap(v => v.ranking.filter(r => r.name !== name)
      .slice(0, 2).map(r => `${r.name} (${v.lens}): ${r.reason}`))
    return { steal: mine?.steal ?? '', praise: praise.join('; ') }
  }
  phase('Polish')
  await parallel(crew.map(m => () => {
    const f = stealFor(m.name)
    return agent(
      `You are "${m.name}", worktree ${m.dir}. Panel leader this round: ${top}.\n`
      + `Your own plan to steal: ${f.steal}\n`
      + `Strengths reviewers praised in others: ${f.praise}\n\n`
      + `Revise your solution: KEEP YOUR IDENTITY, adopt only what is genuinely `
      + `better — do NOT just copy the leader (that collapses diversity). `
      + `Then git add -A && git commit -m "${m.name}: round ${round + 1}".`,
      { phase: 'Polish', label: `polish:${m.name}` })
  }))
}
