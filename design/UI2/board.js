const screen = document.querySelector('#screen');
const button = (label, style = '', title = '') =>
  `<button type="button" class="${style}" ${style === 'disabled' ? 'disabled' : ''} title="${title}">${label}</button>`;
const link = (label, target, style = '') => `<a class="button ${style}" href="#${target}">${label}</a>`;
const tabs = (...labels) => `<div class="tabs">${labels.map((label, i) => button(label, i ? 'tab' : 'tab selected')).join('')}</div>`;
const heading = (title, description, action = '') => `<div class="heading"><div><h1>${title}</h1><p>${description}</p></div>${action}</div>`;
const pill = (text, style = '') => `<span class="pill ${style}">${text}</span>`;
const table = (headers, rows) => `<div class="table-box"><table><thead><tr>${headers.map(x => '<th scope="col">' + x + '</th>').join('')}</tr></thead><tbody>${rows.map((row, i) => `<tr ${i === 0 ? 'class="current"' : ''}>${row.map(x => '<td>' + x + '</td>').join('')}</tr>`).join('')}</tbody></table></div>`;
const row = (title, description, control) => `<div class="setting"><div><b>${title}</b><span>${description}</span></div>${control}</div>`;
const toggle = on => button(on ? 'On' : 'Off', on ? 'toggle selected' : 'toggle');
const section = title => `<h2 class="section">${title}</h2>`;
const card = (title, description, target) => `<article class="card"><h3>${title}</h3><p>${description}</p><div class="actions">${link('Open ' + title, target)}</div></article>`;

function alertCard(title, description, state, route, safePreview, selected = false) {
  return `<article class="card alert-card ${selected ? 'selected-card' : ''}"><div class="row between"><h3>${title}</h3>${state}</div><p>${description}</p><div class="actions">${route ? link('Configure', route, selected ? 'primary' : '') : button('Configure')} ${safePreview ? link('Test alert', route + '-test') : ''}</div></article>`;
}

function alerts(detail, testing) {
  const bounty = detail === 'bounty';
  const active = bounty ? 'Bounty Spotted' : 'Guild Death';
  const cards = [
    alertCard('Guild Death', 'Shows a popup for reported guild deaths.', pill('Popup enabled'), 'alerts-death', true, !bounty),
    alertCard('Bounty Spotted', 'Shows a popup for a matched bounty target.', pill('Popup enabled'), 'alerts-bounty', true, bounty),
    alertCard('Calls to Arms', 'Shows incoming Calls to Arms in chat.', pill('Chat enabled'), '', false),
    alertCard('Report reminders', 'Shows local reminders in chat.', pill('Off', 'off'), '', false),
    alertCard('Guild LFG notices', 'Interest, invitations, and matching listings.', pill('Mixed'), 'lfg', false),
    alertCard('Ready Check', 'Feedback for raid readiness checks.', pill('Enabled'), 'raid', false),
    alertCard('Death Protection', 'Existing release protection notices.', pill('Enabled'), 'raid', false),
    alertCard('Combat displays', 'Existing combat tools and Battle Resurrection.', pill('Mixed'), 'raid', false)
  ];
  const texture = bounty ? 'BountyAlertFrame' : 'DeathAlertFrame';
  const extras = bounty
    ? row('Friendly bounty test mode','Use the existing friendly target test setting.', toggle(false))
    : row('Chat alerts','Show death reports in chat.', toggle(true))
      + row('Hide in combat','Suppress the local popup during combat.', toggle(false))
      + row('Guild broadcast','Share qualifying death reports.', toggle(true))
      + row('Smart Mode','Threshold, detection window, and quiet period.', toggle(true))
      + '<div class="rule"><p>Unique deaths · Detection window · Quiet period</p><div class="row"><input size="3" aria-label="Unique deaths" value="5"><input size="4" aria-label="Detection window" value="45 s"><input size="4" aria-label="Quiet period" value="90 s"></div><div class="actions">' + button('Apply Smart Mode') + button('Reset Defaults') + '</div></div>';
  const detailCard = `<aside class="card details"><h2>${active}</h2>
   ${row('Show popup','Display this alert on screen.', toggle(true))}
   ${row('Play sound','Uses the existing alert sound.', toggle(true))}
   ${row('Size','Adjust the scale of the popup.', '<div class="row">' + button('−', '', 'Decrease size') + '100%' + button('+', '', 'Increase size') + '</div>')}
   ${row('Duration','Time before the popup closes.', '<div class="row">' + button('−', '', 'Decrease duration') + (bounty ? '7 s' : '8 s') + button('+', '', 'Increase duration') + '</div>')}
   <h2 class="section">Screen Position</h2>
   <div class="preview"><img src="assets/${texture}.png" alt="Existing ${active} alert frame artwork"><span>${bounty ? 'Example Target · Hillsbrad Foothills' : 'Guildmate · Hillsbrad Foothills'}</span></div>
   <p class="preview-note">${testing ? 'Local test preview shown.' : 'Positioning mode example. Drag the popup and lock its position when done.'}</p>
   <div class="actions">${button('Move Alert','primary')}${button('Reset Position')}${button('Lock position')}</div>
   <div class="rule">${extras}</div></aside>`;
  return heading('Alert Command Center','Configure, place, and test your existing alerts.',link('Settings Center','settings'))
    + '<div class="card tools">' + row('All alert sounds','Master sound switch for supported alerts.',toggle(true)) + '</div>'
    + '<div class="spread"><div class="grid">' + cards.join('') + '</div>' + detailCard + '</div>';
}

const pages = {
  home: ['Command Center', () => heading('Command Center','Guild activity and shortcuts to your everyday tools.')
    + '<div class="grid three">' + [['2','Active Calls to Arms'],['4','Active bounties'],['8','Recorded sightings']].map(([n,l]) => `<div class="card metric"><strong>${n}</strong><span>${l}</span></div>`).join('') + '</div>'
    + section('Quick Access') + '<div class="grid">' + [
      card('Find a Group','Browse groups or start a listing.','lfg'), card('PvP Operations','Review active Calls to Arms and commanders.','war'),
      card('Raid Operations','Open assignments, sign-ups, and raid tools.','raid'), card('Guild Services','Find professions and learned recipes.','services'),
      card('Settings','Find options for the window, sharing, and alerts.','settings')
    ].join('') + '</div>'],
  settings: ['Settings Center', () => heading('Settings Center','Find an existing setting or browse by category.')
    + '<div class="row tools"><input aria-label="Settings search example" size="35" value="guild death">' + link('Open Alerts','alerts','primary') + '</div>'
    + '<div class="spread"><div class="stack"><div class="card"><h2>Matching Settings</h2>'
    + row('Guild Death Alerts','Alerts · Account-wide · Popup, sound, position, and duration.',link('Open','alerts-death'))
    + row('Smart Mode','World PvP · Account-wide · Threshold and suppression window.',link('Open','alerts-death'))
    + row('Guild Death Broadcast','World PvP · Account-wide · Share qualifying death reports.',link('Open','alerts-death'))
    + '</div><div class="card"><h2>Interface & Minimap</h2>' + row('Window Scale','Account-wide · War Command window size.',button('100%'))
    + row('Minimap Launcher','Account-wide · Show the KWC launcher.',toggle(true)) + '</div></div>'
    + '<div class="card"><h2>Categories</h2><div class="stack">' + ['General','Interface & Minimap','Alerts','World PvP','Raids','Guild & Sharing','Sync & Network','Advanced'].map(x => x === 'Alerts' ? link(x,'alerts','selected') : button(x)).join('') + '</div></div></div>'],
  alerts: ['Alert Command Center', () => alerts('death', false)],
  'alerts-death': ['Alert Command Center', () => alerts('death', false)],
  'alerts-death-test': ['Alert Command Center', () => alerts('death', true)],
  'alerts-bounty': ['Alert Command Center', () => alerts('bounty', false)],
  'alerts-bounty-test': ['Alert Command Center', () => alerts('bounty', true)],
  war: ['War Room', () => heading('War Room','Active Calls to Arms, command, and response totals.',button('New Call to Arms','primary'))
    + '<div class="row tools">' + button('Request guild sync') + button('Scout Network') + '</div><div class="stack">'
    + '<article class="card"><div class="row between"><h3>Defend Tarren Mill</h3>' + pill('Urgent','priority') + '</div><p>Hillsbrad Foothills · Commander Stoneward</p><div class="rule">6 coming · 2 maybe · 1 busy</div><div class="actions">' + button('Respond') + button('After-action report') + button('View Operation','primary') + '</div></article>'
    + '<article class="card"><div class="row between"><h3>Scout the Crossroads</h3>' + pill('Normal') + '</div><p>The Barrens · Commander Ironmark</p><div class="rule">3 coming · 1 maybe · 0 busy</div><div class="actions">' + button('Respond') + button('After-action report') + button('View Operation') + '</div></article></div>'],
  bounty: ['Bounty Board', () => heading('Bounty Board','Track targets, sightings, and claims.',link('Bounty Alert Settings','alerts-bounty'))
    + '<div class="row tools">' + button('New Bounty','primary') + button('Report Sighting') + button('Capture Target','disabled','Target a valid player first.') + button('Report to Guild') + '</div>'
    + tabs('Active','Completed','All') + table(['Target','Reward','Last sighting','State'],[['Example Target','1 g','Hillsbrad Foothills',pill('Active')],['Duskwalker','2 g','Arathi Highlands',pill('Active')],['Blackiron','50 s','Unknown',pill('Active')]])
    + '<div class="section card"><h2>Example Target</h2><p>Selected bounty · Last reported in Hillsbrad Foothills.</p><div class="actions">' + button('View Details') + button('Sighting History') + '</div></div>'],
  lfg: ['Guild LFG', () => heading('Guild LFG','Browse groups posted by guildmates.')
    + tabs('Browse Groups','Create Listing','My Listings')
    + '<div class="row tools"><select aria-label="Activity"><option>All activities</option></select><select aria-label="Role"><option>All roles</option></select><input aria-label="Level" size="6" placeholder="Level">' + button('Apply') + button('Refresh') + '</div>'
    + table(['Activity','Leader','Party','Age'],[['Blackrock Depths','Stoneward','3 / 5','12m'],['Hillsbrad patrol','Ironmark','2 / 5','21m']])
    + '<section class="section card"><h2>Blackrock Depths</h2><p>Dungeon · Level 53–60 · Tank, Healer</p><p>Starting at the entrance.</p><div class="actions">' + button('Interested','primary') + button('Whisper Leader') + '</div></section>'
    + '<div class="row tools">' + button('Interest notices: On') + button('Invites: On') + button('Matches: Off') + '</div>'],
  services: ['Guild Services', () => heading('Guild Services','Find a guildmate by profession or learned recipe.',link('Sharing Settings','settings'))
    + tabs('Recipes','Professions','Overview')
    + '<div class="card tools"><div class="row between"><b>Profession and learned recipe sharing</b>' + pill('Sharing on') + '</div><p>This character shares with the verified guild.</p></div>'
    + '<div class="row tools"><input aria-label="Character" size="11" placeholder="Character"><input aria-label="Profession" size="11" placeholder="Profession"><input aria-label="Recipe" size="16" placeholder="Recipe or crafted item">' + button('Apply Filters','primary') + button('Sort: Character') + button('Refresh') + '</div>'
    + table(['Recipe','Character','Profession','Updated'],[['Elixir of Fortitude','Steelbloom','Alchemy','Today'],['Heavy Runecloth Bandage','Stoneward','First Aid','Today'],['Thorium Shield Spike','Ironmark','Blacksmithing','Yesterday']])],
  raid: ['Raid Operations', () => heading('Raid Operations','Open raid assignments, sign-ups, and preparation tools.')
    + tabs('Overview','Raid Command','Raid Sign-Ups')
    + '<div class="grid"><article class="card"><h2>Operations</h2><div class="stack">' + button('Attendance & Records') + button('Raid Roster') + '</div></article>'
    + '<article class="card"><h2>Preparation</h2><div class="stack">' + button('Ready Checks') + button('Invitations') + button('Raid Notes') + '</div></article>'
    + '<article class="card"><h2>In Combat</h2><div class="stack">' + button('Combat Tools') + button('Battle Resurrection Button') + button('Death Protection') + '</div></article>'
    + '<article class="card"><h2>Battle Resurrection</h2><p>Show the indicator while in a raid.</p><div class="actions">' + pill('Setting enabled') + button('Show Preview','disabled','Join a raid to preview the indicator.') + '</div><p class="minor">Preview is available while in a raid outside combat.</p></article></div>'],
  components: ['Design System', () => heading('Design System','Palette, type scale, and reusable interface states.')
    + '<div class="grid three">' + [['Charcoal','#141518'],['Graphite','#1d1e22'],['Blackened steel','#35363d'],['Bronze','#d3b486'],['Crimson','#702936'],['Off-white','#f2ede6']].map(([name,color]) => `<div class="card token"><div class="swatch" style="background:${color}"></div>${name} · ${color}</div>`).join('') + '</div>'
    + section('Typography') + '<div class="card"><h1>Page heading · 29 px</h1><h2>Section heading · 16 px</h2><p>Body, buttons, and rows · 14 px</p><small>Secondary text and tooltips · 12 px</small></div>'
    + section('Controls and States') + '<div class="card"><div class="row">' + button('Default') + button('Hover','hover') + button('Primary','primary') + button('Selected','selected') + button('Unavailable','disabled') + toggle(true) + toggle(false) + '</div><div class="actions"><input aria-label="Search example" placeholder="Search settings"><select aria-label="Activity filter"><option>All activities</option></select></div></div>'
    + section('Table Styling') + table(['Name','Status'],[['Selected row',pill('Enabled')],['Default row',pill('Off','off')]])
    + section('Alert Card') + alertCard('Guild Death','Shows a popup for reported guild deaths.',pill('Popup enabled'),'alerts-death',true)]
};

function render() {
  const page = location.hash.slice(1) || 'home';
  const [title, draw] = pages[page] || pages.home;
  document.querySelector('#crumb').textContent = title;
  screen.innerHTML = draw();
  const navPage = page.startsWith('alerts') ? 'alerts' : page;
  for (const item of document.querySelectorAll('nav a')) {
    if (item.hash === '#' + navPage) item.setAttribute('aria-current', 'page');
    else item.removeAttribute('aria-current');
  }
}
addEventListener('hashchange', render);
render();
