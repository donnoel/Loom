---
layout: default
title: Loom
---

<section class="hero" aria-labelledby="hero-title">
  <div class="hero__copy">
    <p class="eyebrow">Native macOS <span aria-hidden="true">·</span> Offline-first AI</p>
    <h1 id="hero-title">Local AI that feels like a Mac app.</h1>
    <p class="hero__lede">Loom brings local models, durable conversations, files, notes, and model comparison into one calm workspace—without sending your chats away.</p>
    <div class="hero__actions">
      <a class="button button--primary" href="{{ site.github_url }}">View on GitHub <span aria-hidden="true">↗</span></a>
      <a class="button button--quiet" href="#session-flow">See a session unfold</a>
    </div>
    <ul class="signal-list" aria-label="Project foundation">
      <li>SwiftUI</li>
      <li>macOS</li>
      <li>Ollama local</li>
      <li>JSONL storage</li>
    </ul>
  </div>

  <aside class="status-card" aria-labelledby="build-status-title">
    <div class="status-card__topline">
      <span class="status-pill"><span class="status-dot" aria-hidden="true"></span>{{ site.status_label }}</span>
      <span class="status-card__meta">On this Mac</span>
    </div>
    <div class="house-mark" aria-hidden="true">
      <span></span><span></span><span></span><span></span>
    </div>
    <p class="status-card__kicker">Current workspace</p>
    <h2 id="build-status-title">Your chats stay local.<br>Your work stays yours.</h2>
    <dl class="status-list">
      <div><dt>Local model chat</dt><dd>Ready</dd></div>
      <div><dt>Disk-backed sessions</dt><dd>Ready</dd></div>
      <div><dt>Cloud account</dt><dd>Not required</dd></div>
    </dl>
  </aside>
</section>

<section class="section" aria-labelledby="principles-title">
  <div class="section-heading">
    <p class="eyebrow">A private working space</p>
    <h2 id="principles-title">Capable enough for real work. Quiet enough to think.</h2>
    <p>Loom treats local AI like a durable desktop tool: conversations behave like documents, controls use plain language, and the machinery stays out of your way.</p>
  </div>

  <div class="principle-grid">
    <article class="principle-card">
      <span class="card-number" aria-hidden="true">01</span>
      <h3>Local by default</h3>
      <p>Ollama runs the model on your Mac, while chat history, notes, attachments, and preferences remain in local app storage.</p>
    </article>
    <article class="principle-card">
      <span class="card-number" aria-hidden="true">02</span>
      <h3>Resilient conversations</h3>
      <p>Messages save incrementally, replies stream live, and stopping generation keeps the useful partial response.</p>
    </article>
    <article class="principle-card">
      <span class="card-number" aria-hidden="true">03</span>
      <h3>Human setup guidance</h3>
      <p>When a model or local runtime is missing, Loom explains the next step without exposing ports, APIs, or infrastructure jargon.</p>
    </article>
  </div>
</section>

<section class="section section--split" id="session-flow" aria-labelledby="session-title">
  <article class="resident-card">
    <div class="resident-card__header">
      <div class="resident-icon" aria-hidden="true">
        <span></span><span></span><span></span>
      </div>
      <div>
        <p class="eyebrow">One local session</p>
        <h2 id="session-title">A conversation with a workspace around it</h2>
      </div>
    </div>
    <p class="resident-card__summary">Each session keeps its transcript, model context, optional files, scratchpad, and reply preferences together—ready when you return.</p>
    <div class="boundary-note">
      <strong>Files you can understand</strong>
      <span>Metadata · Append-only messages · Notes · Memory</span>
    </div>
    <ul class="capability-list">
      <li><span aria-hidden="true">✓</span> Search, pin, archive, rename, and export</li>
      <li><span aria-hidden="true">✓</span> Attach local text and PDF context</li>
      <li><span aria-hidden="true">✓</span> Compare two installed models side by side</li>
      <li><span aria-hidden="true">✓</span> Keep a scratchpad outside the transcript</li>
    </ul>
  </article>

  <div class="run-flow" aria-labelledby="flow-title">
    <p class="eyebrow">The local chat loop</p>
    <h2 id="flow-title">Start simply. Keep everything useful.</h2>
    <ol>
      <li><span>01</span><div><strong>Choose a model</strong><p>Use one already installed through Ollama.</p></div></li>
      <li><span>02</span><div><strong>Create a session</strong><p>Begin with a durable local workspace.</p></div></li>
      <li><span>03</span><div><strong>Add context</strong><p>Attach files or tune conversation history.</p></div></li>
      <li><span>04</span><div><strong>Send a request</strong><p>Watch the local reply stream as it arrives.</p></div></li>
      <li><span>05</span><div><strong>Stop when needed</strong><p>Keep the partial answer instead of losing it.</p></div></li>
      <li><span>06</span><div><strong>Return later</strong><p>Search or reopen the saved session.</p></div></li>
    </ol>
  </div>
</section>

<section class="section foundation" aria-labelledby="foundation-title">
  <div>
    <p class="eyebrow">Built for trust</p>
    <h2 id="foundation-title">The local foundation stays visible.</h2>
  </div>
  <p>Loom stores sessions in Application Support with atomic metadata writes and append-only message history, while the toolbar keeps local runtime readiness visible at a glance.</p>
</section>
