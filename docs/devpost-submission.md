  # Froyou
  
  **Arm AI Optimization Challenge 2026 — Track 1: Optimization output · Edge AI**
  
  > **Setup, build and validation instructions are in the
  > [README on GitHub](https://github.com/varunbhalerao56/froyou#getting-started).**
  > A TestFlight link is on the submission page if you'd rather just run it.
  
  A local-first iOS journal that notices what you keep coming back to. You talk or
  type; it transcribes, reads the mood, embeds every sentence, groups those
  embeddings across everything you've ever written, and names the groups — so it
  can tell you that six logs written six different ways, with no word in common,
  were all the same worry.
  
  It runs four on-device models on the Arm silicon already in your phone and ships
  **zero bytes of model weights** to do it. The download is **38.8 MB**, and the
  largest thing in it is the font. No server, no account, no network call.
  
  ---
  
  ## Inspiration
  
  I deal with anxiety sometimes, and the hard part isn't the feeling — it's the
  loop. The same worry arrives wearing a different outfit every day. Monday: "I
  think I said the wrong thing in standup." Wednesday: "I don't think they're
  happy with the timeline." Sunday: "I should probably talk to my manager." Three
  sentences with almost no words in common; no keyword search connects them. But
  they're one thought, and I'd been carrying it a week without noticing, because
  each instance felt reasonable on its own.
  
  That's what I wanted a computer to do: not advise, not diagnose, not score my
  mood out of ten — just **notice**, and say it back.
  
  Three things followed. It had to be **boring to use** (every journalling app I
  tried wanted a mood emoji, a prompt, a tag, a sleep rating — when you're already
  in a loop, a form is another loop). It had to **check on me** with a question
  that knows what yesterday was like, not a generic 9 p.m. push. And it had to be
  **comforting to open** — your own photos behind a caption you wrote, not a
  dashboard with a streak counter.
  
  ---
  
  ## What it does
  
  **Talk or type.** Recording streams live from iOS 26's `SpeechTranscriber`, each
  word fading in as it lands and quietly revising itself when the recognizer
  changes its mind.
  
  **It finds the loops.** Every sentence becomes a 512-dim `NLContextualEmbedding`
  vector in ObjectBox. Vectors are grouped by similarity against a threshold
  derived from your own writing, and the whole corpus is regrouped from scratch
  when it's grown or shifted enough to matter. Apple's on-device language model
  names each group: "Deadline moved." "Not sleeping." "The conversation I keep not
  having."
  
  **It shows you the week.** After five logs, an analytics view lists themes that
  recurred in the last seven days — the name, how many entries touched it, and the
  sentences that produced the count, always one tap away. A claim about your own
  week should be checkable.
  
  **It checks in.** If yesterday averaged below −0.15 sentiment, today's home
  screen carries one short, warm, open question written by the on-device model
  from yesterday's themes. Never in the moment — always the day after. Never on
  one bad entry inside a fine day — always on the day's average. It clears when
  you log. A second notification can deliver the same question at 9 AM. If the
  model isn't available, **no question appears at all** — a canned one would be
  worse than silence.
  
  **It stays yours.** Airplane mode changes nothing. No account, no sync, no
  telemetry, no network code to audit.
  
  ---
  
  ## How we built it
  
  **The strategy is: rent the models, own the pipeline.**
  
  The conventional private-AI app bundles quantized models and then fights to keep
  the download under half a gigabyte. Froyou takes the opposite bet. iOS 26 ships
  `SpeechTranscriber`, `NLTagger`, `NLContextualEmbedding` and
  `SystemLanguageModel` as system services — compiled for the Arm CPU and Neural
  Engine, resident once for every app on the device. The marginal disk cost of the
  AI is 0 MB, the memory cost is the OS's, and the inference path is Apple's own,
  already scheduled onto the ANE by code that knows the hardware far better than
  we could.
  
  The cost is real and shapes everything below: **you cannot fine-tune, quantize,
  swap, or properly profile a model you don't own.** Every optimization has to
  happen upstream or downstream of it.
  
  | Channel | Framework | What it does here |
  |---|---|---|
  | `app/speech` | `SpeechAnalyzer` / `SpeechTranscriber` | Streaming transcription with live revision. EventChannel for the stream, MethodChannel for control. |
  | `app/nlp` | `NLTokenizer`, `NLTagger`, `NLContextualEmbedding` | Sentence splitting, sentiment, 512-dim embeddings, mean-pooled natively. |
  | `app/genai` | `SystemLanguageModel` (Foundation Models) | Theme names, entry keywords, the follow-up question — `@Generable` guided generation. |
  | — | ObjectBox | On-device vector store. An HNSW index is declared and deliberately **not** used — see Challenges. |
  
  The interesting part: **none of these models knows about the others.** The
  embedder doesn't know it's feeding a clustering algorithm; the language model
  doesn't know the groups it's naming came from cosine similarity. Making four
  independent black boxes into one coherent product is where the work — and the
  optimization opportunity — turned out to be.
  
  ### What happens when you save a log
  
  ```
  text ─┬─> KeywordNamer → SystemLanguageModel ──> entry.keywords ──► [log card]
        ├─> NLTagger sentiment ────────────────> entry.moodScore ──► [mood dot]
        └─> NLContextualEmbedding ──centred cosine ≥ Otsu──> ThemeCluster
                  └─> ClusterNamer.relabelAll → SystemLanguageModel ► [Analytics]
  ```
  
  **The three branches are independent.** A device where the embedding assets
  never finish downloading still gets a mood dot and card keywords; the entry is
  just stored unclustered. Nothing in the fan-out is a chain.
  
  **The card is written twice, on purpose.** Keywords get a synchronous value the
  instant the entry saves, so a card is never blank; the model's answer overwrites
  it. Phase 1 of a save cannot wait on an inference and must not fail with one.
  
  **Theme naming is deferred and global.** `relabelAll` renames *every* group in a
  single request, never just the one that changed — the model can only make names
  distinguish each other if it sees them side by side.
  
  ### Zero bundled weights: the numbers
  
  No model files at all. Not a quantized encoder, not a GloVe table, not an ONNX
  runtime. The shipped `flutter build ipa --release`:
  
  | Component | Size | What it is |
  |---|---:|---|
  | `flutter_assets/fonts` | **21.0 MB** | SF Pro Rounded, four weights |
  | `Flutter.framework` | 9.8 MB | the Flutter engine |
  | `App` (Dart AOT snapshot) | 7.3 MB | **all of Froyou's own code** |
  | `ObjectBox.framework` | 2.7 MB | the on-device vector database |
  | `Assets.car` | 0.5 MB | the app icon, 15 sizes |
  | `Runner` | 0.5 MB | the three Swift channels + bootstrap |
  | everything else | ~0.4 MB | plugin frameworks and resource bundles |
  | **Total `.app`** | **43 MB** | uncompressed on disk |
  | **Shipped `.ipa`** | **38.8 MB** | what a user downloads |
  | **Model weights** | **0 bytes** | |
  
  **The largest asset in this AI app is the typeface.** Four SF Pro Rounded
  weights outweigh the Flutter engine, the Dart snapshot, the vector database and
  the Swift channels *combined*. Cutting the fonts would shrink the download 49%;
  cutting the AI would shrink it 0%.
  
  **What the same app would cost with bundled weights.** Take the modest version —
  a MiniLM-class sentence encoder at INT8 (~25 MB), a WhisperTiny/Small-class
  speech model (~40–250 MB), and drop generative naming entirely because you
  can't afford it:
  
  | Build | Download | Weights |
  |---|---:|---:|
  | Froyou as shipped | **38.8 MB** | 0 |
  | Same features, small bundled encoder + tiny ASR | ~105 MB | ~65 MB |
  | With a real speech model and a 3B INT4 LLM | **~1.8 GB** | ~1.75 GB |
  
  The third row is the honest comparison, because it's the only one that ships
  what Froyou actually does. **A 3B-parameter model at 4-bit is ~1.6 GB of weights
  — roughly 41× the entire Froyou download.** That's why on-device apps that start
  out wanting a language model almost always abandon it and fall back to
  embeddings. Froyou never had to make that trade: a model of that class was
  already installed.
  
  And the App Store cellular-download limit was 200 MB until Apple raised it to
  500 MB — the bundled version of this app is on the wrong side of both.
  
  ### The memory argument is stronger than the disk one
  
  Disk is the visible number. Resident memory is the one that decides whether the
  app *runs*.
  
  **Weights you bundle are weights you page into your own address space, against
  your own jetsam limit.** iOS gives a foreground app a hard memory ceiling in the
  hundreds of megabytes; exceeding it isn't swapping, it's an immediate kill. A 3B
  INT4 model needs ~1.6 GB resident during generation — an app cannot hold that.
  Even the small build pays: an INT8 encoder is tens of MB resident for as long as
  you keep the session warm, plus the runtime's arena, plus the KV cache if you
  generate. Every one of those bytes counts against you, and every one is paid
  again by the next app on the phone that wants the same thing.
  
  **Froyou's inference happens outside the app.** Foundation Models and the Natural
  Language embedding stack run as system services; the app sends a request and
  receives a result. The weights are resident to the OS, not to us — so the model
  does not appear in our footprint, does not compete with the ObjectBox page cache
  or the decoded backdrop photo, and cannot jetsam us. Our own AI-related resident
  cost is the request and the reply: 512 doubles per sentence, and a handful of
  short strings.
  
  Three consequences that matter more than the megabytes:
  
  - **Memory is shared across apps, not duplicated per app.** Three apps using the
    system embedder cost the device one copy. Three apps bundling their own cost
    three.
  - **Cold start doesn't pay a model load.** There is no multi-hundred-MB mmap
    before first use, so the app is interactive immediately; the first *inference*
    may wait on assets, which is why phase 1 of a save never depends on phase 2.
  - **The memory budget goes to the product.** The photo pipeline — a two-pass
    Gaussian at full pane height, a decoded full-resolution backdrop, a snapshot
    raster for the breathing scale — is genuinely memory-hungry and exists only
    because nothing is competing with it for the ceiling.
  
  ### How the grouping actually works
  
  Sentences are grouped on **centred** cosine similarity — the average direction of
  all stored embeddings is subtracted before any comparison, because raw
  embeddings all point roughly the same way regardless of meaning. The threshold
  isn't a constant: **Otsu's method** reads it off the pairwise similarity
  distribution on every pass, with a 4/√512 noise floor underneath so a genuinely
  varied journal can't collapse into one theme.
  
  Grouping is redone from scratch rather than patched, because incremental
  assignment is order-dependent — a theme drifts as it absorbs sentences, and one
  that has swallowed everything becomes a magnet. **But not on every save:**
  `maybeRecluster` rebuilds once per launch, then only when the corpus has grown
  by half again or the average has actually moved.
  
  **And that average comes from the themes, not the sentences** — the single most
  expensive thing in the pipeline before it was fixed. Computing it directly means
  loading thousands of sentences and their 512 floats each, on every save. Each
  theme instead carries a running `sumVector`, so summing *tens of themes* gives
  exactly the same answer — not an approximation — for a fraction of the I/O and
  none of the peak memory.
  
  ### Speed, latency and energy
  
  **Perceived save latency is decoupled from inference entirely.** Raw text commits
  synchronously and the UI updates; sentiment, embeddings, clustering and naming
  run unawaited afterwards on a 30-second budget. Time to "my words are safe" is a
  local write.
  
  **Round-trips are batched where it matters.** `embedSentences` splits *and*
  embeds natively in **one channel crossing instead of N+1**, and detects language
  once over the whole text rather than per sentence (detection on a short sentence
  is unreliable — a quality win as well as a latency one). Each sentence is still
  embedded *separately* inside that call: the model is contextual, so embedding a
  paragraph in one pass would make the same sentence produce different vectors
  depending on its neighbours. Mean-pooling happens **in Swift**, so the channel
  carries 512 doubles per sentence rather than `tokens × 512`. Embedding instances
  are **cached per language** — loading one is expensive and the language rarely
  changes.
  
  **Guided generation as a decode-time optimization.** `@Generable` + `@Guide`
  constrain output to a schema, removing the parse-retry loop. The schemas are
  shaped to minimize *generated tokens*: `ThemeNames` is a flat `[String]` matched
  back **by position** rather than `{id, label}` pairs — making the model echo an
  integer costs tokens and risks a hallucinated id silently renaming the wrong
  theme. The ids never leave Swift.
  
  **A failure latch protects the battery.** `SystemLanguageModel` reporting
  `.available` is necessary but not sufficient — generation additionally needs
  Apple's safety classifier, and where that asset is missing every call fails while
  the model still advertises itself. `GenAiService` counts consecutive failures and
  after **two** stops asking for the session. Without it, a device in that state
  pays a full failed inference on every save, forever.
  
  ### Designing for a model that might not be there
  
  Availability is a hardware-and-settings question, not an OS-version one.
  `SystemLanguageModel` is absent on devices without the neural capacity, absent
  when the user switched it off, and absent while assets download — three states
  demanding *different product responses*, so they're distinct enum values.
  `deviceNotEligible` is permanent and never mentioned to the user;
  `appleIntelligenceNotEnabled` is a setting they control; `modelNotReady` is worth
  retrying.
  
  **And every path degrades rather than breaking.** Speech falls back to typing; a
  device whose embedding assets never arrive still gets sentiment and keywords and
  simply stores the entry unclustered. The follow-up question is the deliberate
  exception — with no model there is no question at all, because a warm open
  question about a day you didn't have is worse than silence.
  
  **Notifications compose their text at scheduling time.** iOS wants the body when
  you schedule, and nothing of ours runs when it fires — there's no hook to write
  a line at 9 AM. So the question is composed at the end of a save, the only moment
  the day's mood and themes are known and the model is warm. Consequence: the armed
  question describes the day your last log belongs to, and a later log rewrites it.
  
  ### Why this compounds
  
  Every optimization in a bundled-model app is a one-time purchase that starts
  depreciating on ship. Your INT8 encoder is as good as it will ever be; improving
  it means a new model, re-quantizing, re-validating, and more megabytes.
  
  Froyou's model layer is a **subscription to Apple's roadmap**, paid in lock-in.
  A better `SpeechTranscriber` in iOS 27 means every install transcribes better. A
  less anisotropic embedder means the centring step keeps working and the groups
  get cleaner. Apple ships a new Neural Engine roughly annually, and an app that
  calls the system model gets that speedup in full, for free.
  
  ---
  
  ## Challenges we ran into
  
  **Cosine similarity didn't work, and it took a while to believe it.**
  
  An embedding turns a sentence into a *direction* in 512-dim space, and cosine
  similarity measures the angle: 1.0 identical, 0 unrelated. So the obvious design
  is embed, compare, join above a threshold.
  
  It fails because of **anisotropy** — the vectors don't use the space. They're
  crammed into a narrow cone, all pointing roughly the same way *before* you
  consider what they say. Picture a crowd where everyone happens to face north:
  which way people face tells you nothing about who's talking to whom.
  
  Measured on a real device, sentences about *cooking*, *an audiobook* and *a
  relationship* scored **0.86, 0.91 and 0.94** against the same theme — three
  unrelated topics in a band **0.076 wide**, all above 0.85. No threshold fits in
  there. This also rules out the obvious optimization: ObjectBox has an HNSW index
  and `nearestNeighborsF32` right there, but it can only rank *raw* vectors —
  exactly the ones carrying no signal. The first tool everyone reaches for is the
  one this problem forbids.
  
  **Centring is the fix.** Compute the average direction of every stored embedding
  — the "north" they're all facing — subtract it, rescale. What's left is only the
  part that makes a sentence *different*. The same device data then reads unrelated
  pairs at a median of **−0.036** and related pairs out at **p99 0.513**.
  
  **Then the threshold ate three more attempts:**
  
  | Value | Where it came from | How it failed |
  |---|---|---|
  | **0.55** | the synthetic seed, where same-topic vectors score 0.88 | 26 sentences → **25 themes** |
  | **4/√512 ≈ 0.177** | the noise floor — four sigma past chance | sat **below the real user's p90**; filed an audiobook under work |
  | **p90** | "the top tenth of pairs are related" | the seed's share is a *fifth* — broke the seed |
  
  The noise floor is the instructive failure: it's what the mathematics hands you,
  it's provably beyond chance, and it's still wrong — "beyond chance" and "about
  the same subject" are not the same question.
  
  **What works is Otsu's method**, borrowed from image scanning where it decides
  which greys are ink and which are paper. Plot every pairwise similarity and you
  get two humps — a big one near zero for sentences that merely share a language,
  a smaller one further right for sentences that share a subject. Otsu finds the
  dip, assuming nothing about where it sits or how big either hump is, which is why
  it survives both a real journal and a synthetic seed whose distributions look
  nothing alike. On the seed it picks **0.333**, catches exactly the **13
  same-topic pairs out of 66**, and rebuilds exactly the **4 seeded topics**.
  
  **Then, with the groups finally correct, the names were still wrong.** The
  original design had no language model in it — c-TF-IDF named the themes. It's a
  good algorithm that produced useless names, for a reason invisible while building
  it: **a statistical extractor can only return terms that literally appear in the
  text.** That's precisely what this app exists to defeat. The embedding notices
  that "my manager pushed the date again" and "the timeline slipped" belong
  together; the labeler then takes that correct group and, having only those
  sentences' vocabulary, calls the theme *"pushed"* or *"timeline."* Grouping
  solved the synonym problem and naming immediately reintroduced it.
  
  So naming was rewritten model-first: `SystemLanguageModel` gets the group's most
  central sentences and writes a name that need not contain any word from any of
  them. There's now a `kModelOnlyLabels` switch, currently on, that disables every
  statistical fallback so a blank label means *the model declined* rather than the
  statistics quietly filling in.
  
  **A model that reports itself available and then fails every call.** In the
  Simulator `SystemLanguageModel` reports `.available` and generation still fails —
  `SensitiveContentAnalysisML Code=15 → ModelManagerError 1026`, Apple's safety
  classifier, unprovisioned there. That lesson is now the failure latch, and it
  means **real model output can only be verified on a physical A17 Pro or newer**,
  which shapes the whole test strategy.
  
  **A performance regression that looked free.** Home had a slow Ken Burns drift on
  the backdrop — a transform above a `RepaintBoundary`, which every mental model
  says is compositor-only and therefore free. It was the most expensive thing in
  the app: a raster cache will not hold a layer whose transform changes every
  frame, so the entire backdrop, two-pass Gaussian included, re-rendered at full
  DPR on every frame Home sat *idle*. Deleting it made idle Home actually idle.
  Finding it required disbelieving the abstraction.
  
  **Timezone-correct reminders are a trap.** The `timezone` package ships the zone
  database but can't tell where the device is, so `tz.local` stays UTC and a 21:00
  reminder fires at 21:00 **UTC** — plausible enough to ship and only detectable by
  *waiting*. `flutter_timezone` supplies the IANA name; if it fails, reminders
  switch off rather than firing at the wrong hour.
  
  **Testing an app built on models that don't exist in CI.** Anything that saves a
  log asks the model if it's available; unmocked, that never completes under the
  fake clock and the test hangs to its timeout — this once turned an 80-second
  suite into twenty minutes. Both the genai and speech mocks are now first-class
  and documented as landmines.
  
  ---
  
  ## Accomplishments we're proud of
  
  **Generative theme naming on a phone at zero bundle cost** — the feature a
  bundled-model app has to abandon as too heavy, in a 38.8 MB download that a
  single quantized speech model would have dwarfed.
  
  **A model-quality fix on a model we don't control.** From an unusable 0.076-wide
  band — every topic scoring 0.86–0.94 against every other — to unrelated pairs at
  a median of −0.036 and related pairs at p99 0.513, achieved entirely in the
  pipeline. This is the part that generalizes: anyone using pooled contextual
  embeddings for similarity has this problem, probably without knowing it.
  
  **Offline as a structural property.** Not a toggle — there is no network code to
  audit.
  
  **Three degradation tiers invisible from the UI.** The same build is coherent on
  an A17 Pro with Apple Intelligence on, on an older iOS 26 device, and in a
  Simulator where generation is impossible. Only the boot log knows which you're
  in.
  
  **An interface you're glad to open.** 190 tests, golden-covered,
  contrast-verified at 4.5:1 across every preset × brightness × tint. A journalling
  app that doesn't look like a form.
  
  ---
  
  ## What we learned
  
  **The best mobile-AI optimization available today is often not shipping a
  model.** Everyone benchmarks tokens/sec; nobody benchmarks the 500 MB download
  that made a user abandon the install, or the resident gigabyte that gets the app
  jetsammed. On Arm specifically, platform models are the only way to get the
  vendor's own ANE scheduling for free.
  
  **Embeddings are geometry, and the geometry isn't what you assume.** Anisotropy
  is a property of every pooled contextual embedding model and it silently destroys
  threshold-based systems. Centre your vectors before you compare them.
  
  **A defensible constant is still a constant.** Every threshold we derived from
  first principles was wrong on some corpus, because each quietly assumed the shape
  of a distribution it had never seen. What worked was refusing to pick a number
  and letting an algorithm read the valley out of the data on every pass.
  
  **Grouping and naming are two different jobs.** Embeddings are excellent at
  deciding what belongs together and structurally incapable of saying what it is.
  The tell was that the groups were right while the names were nonsense.
  
  **Availability is a spectrum, not a boolean** — including one state where the
  model claims to be there and isn't.
  
  **Restraint is the feature.** In a mental-health context the design work is
  mostly deciding what not to do. No auto-detected distortions, no streaks, no
  score, and no question at all rather than a canned one.
  
  ---
  
  ## What's next
  
  **CBT structure on top of the logs** — tagging entries against the vocabulary of
  Cognitive Behavioural Therapy so a theme reads "the conversation I keep not
  having · mind-reading · anxious." Non-negotiable: **suggested, never asserted.**
  
  **Enhanced transcription** — speaker-aware segmentation, disfluency handling,
  custom vocabulary for the names in someone's own life. Most of it arrives free as
  `SpeechTranscriber` improves.
  
  **Multimedia notes** — voice memos kept as audio, photos read with Vision, all
  embedded into the same 512-dim space so a photo can join a theme like a sentence.
  
  **Import from elsewhere** — Apple Notes, Day One, Journal, markdown, Health's
  State of Mind. Three years of journalling should show you your loops on day one.
  
  **Better analytics** — months rather than a week, which themes are heating and
  cooling, mood trajectory *within* a theme. "This got easier" is more useful than
  "you were sad on Tuesday."
