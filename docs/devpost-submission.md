# Froyou

**Arm AI Optimization Challenge 2026 — Track 3: Mobile AI**

A local-first journal that notices what you keep coming back to. It runs four
separate on-device models on the Arm silicon already in your phone, and ships
**zero bytes of model weights** to do it — in a 48.3 MB app whose largest single
asset is the font.

---

## Project Overview

Froyou is an iOS journal for people who get stuck in thought loops. You talk or
type; it transcribes, reads the mood, embeds every sentence, clusters those
embeddings across everything you've ever written, and names the clusters — so it
can tell you that six logs written six different ways, with no word in common,
were all the same worry. The next morning, if yesterday was hard, the home
screen stops asking "how are you feeling?" and asks about the thing you actually
wrote.

Everything runs on the device. There is no server, no account, and no network
call anywhere in the app.

**What makes it interesting is the strategy, not the feature list.** The
conventional way to build a private on-device AI app is to bundle quantized
models — a text encoder, maybe a vision encoder, a word-vector table — and then
spend the project fighting to keep the download under half a gigabyte. Froyou
takes the opposite bet: **rent the models the OS already ships, and spend the
entire optimization budget on the pipeline around them.**

iOS 26 ships `SpeechTranscriber`, `NLTagger`, `NLContextualEmbedding` and
`SystemLanguageModel` as system services, all compiled for the Arm CPU/ANE and
all resident once for every app on the device. Using them means the marginal
on-disk cost of Froyou's AI is **0 MB**, the marginal memory cost is shared with
the rest of the OS, and the inference path is Apple's own — already scheduled
onto the ANE and the Arm performance cores rather than something we hand-tuned.

That bet has a consequence that's the real reason to make it: **Froyou gets
better when iOS updates, not when we ship.** When Apple improves
`SpeechTranscriber`'s accuracy or `SystemLanguageModel`'s reasoning in iOS 27,
every Froyou install improves overnight without a byte moving. We are not
maintaining a model. We are maintaining the thing that makes a model useful.

It also has a cost, and being honest about that cost is most of the engineering
here: **you cannot fine-tune, quantize, swap, or profile a model you don't
own.** Every optimization has to happen upstream of it or downstream of it. That
constraint is what this submission is actually about.

**Why it should win:** because the single highest-leverage optimization
available on mobile AI today is *not shipping the model*, and almost nobody
builds that way — and because doing it properly forces you to solve the problems
that a bundled model lets you paper over. The headline is downstream of that: a
**model-quality fix that made clustering work at all, achieved without touching
the model**, on embeddings we can't retrain. Details below.

---

## Inspiration

This one is personal.

I deal with anxiety sometimes, and the hardest part isn't the feeling — it's the
loop. The same worry arrives wearing a different outfit every day. Monday it's
"I think I said the wrong thing in standup." Wednesday it's "I don't think
they're happy with the timeline." Sunday it's "I should probably have a
conversation with my manager." Those are three sentences with almost no words in
common and no keyword search on earth connects them. But they're one thought,
and I've been carrying it for a week without noticing, because each individual
instance felt reasonable.

That's the thing I wanted a computer to do: not advise me, not diagnose me, not
score my mood on a scale of one to ten — just **notice**, and say it back.

Two things followed from that:

**It had to be simple to the point of being boring.** Every journalling app I
tried wanted me to pick a mood emoji, choose a prompt, tag the entry, rate my
sleep. When you're already stuck in a loop, a form is another loop. Froyou has
one text field and a microphone button. The organizing happens afterwards,
without me.

**It had to check on me.** Not a generic 9 p.m. "time to journal!" push — a
question that knows what yesterday was like. If yesterday averaged out rough,
the next morning the home screen asks something specific and warm, written from
the themes I actually touched. If yesterday was fine, it doesn't bring it up.
And the moment I log today, the question clears, because it's done its job.

And it had to be **comforting to open**. The home screen is your own photos —
whatever you want to be reminded matters — drifting behind a caption you wrote,
blurred and glowing at the edges so it dissolves into the page rather than sits
on it. Not a dashboard. Not a streak counter. A thing you're glad to look at.

The privacy requirement wasn't a feature decision, it was the entry price. I was
never going to type this stuff into something with a server.

---

## What it does

**Talk or type.** Recording streams live from iOS 26's `SpeechTranscriber`, with
each word fading in as it lands and quietly revising itself when the recognizer
changes its mind. Or just type. The compose view clears the whole screen so
there's nothing but the words.

**It reads the entry and forgets you.** Saving is instant. Everything derived —
sentiment, embeddings, clustering, naming — happens afterwards, unawaited, and
none of it can cost you the words you just said.

**It finds the loops.** Every sentence becomes a 512-dimensional
`NLContextualEmbedding` vector, stored in ObjectBox. Those vectors are grouped
by centred cosine similarity against a threshold the app derives from your own
corpus, and the whole corpus is regrouped from scratch whenever it has grown or
shifted enough to be worth it. Each group gets a name from `SystemLanguageModel`.
"Deadline moved." "Not sleeping." "The conversation I keep not having."

**It shows you the week.** After five logs, an analytics view lists the themes
that came up more than once in the last seven days: the name, how many separate
entries touched it, the sentence of yours that sits closest to the cluster's
centre, and the other sentences underneath. A count is a claim about your own
week, and a claim about your own week should be checkable — so the sentences
that produced the count are always one tap away.

**It checks in.** If yesterday's entries averaged below −0.15 sentiment,
tomorrow's home screen replaces the default prompt with one short, warm, open
question written by the on-device model from yesterday's themes and its lowest
entry. Never in the moment — always the day after. Never on one bad entry inside
an otherwise fine day — always on the day's average. It clears when you log.
When the model isn't available, no question appears at all; there is no
statistical fallback for warmth, and a canned one would be worse than silence.

**It stays yours.** Airplane mode changes nothing. There is no account, no sync,
no telemetry, and no network code to audit — the promise is structural, not a
setting.

**Safety framing is load-bearing.** Crisis resources are one tap from Settings.
Cognitive distortions are self-tagged, never auto-detected — a statistical model
telling someone they're catastrophizing is not a thing this app will ever do.

---

## The strategy: rent the models, own the pipeline

Froyou composes four Apple frameworks that were never designed to work together,
across three native channels:

| Channel | Framework | What it does here |
|---|---|---|
| `app/speech` | `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26) | Streaming transcription with live revision. EventChannel for the stream, MethodChannel for control — the split is deliberate. |
| `app/nlp` | `NLTokenizer`, `NLTagger`, `NLContextualEmbedding` | Sentence splitting, sentiment, 512-dim contextual embeddings, mean-pooled natively. |
| `app/genai` | `SystemLanguageModel` (Foundation Models) | Theme names, entry keywords, the follow-up question, the reminder line — all via `@Generable` guided generation. |
| — | ObjectBox | On-device store for 512-dim vectors. An HNSW index is declared but deliberately **not** used for grouping — see the anisotropy section. |

All three channels follow one shape: `register(with:)`, a single-use
main-thread-safe `ChannelReply`, a stable error-code enum matched by name in
Dart, and every unit of work off the platform thread.

The interesting part is that **none of these models knows about the others.**
`NLContextualEmbedding` doesn't know it's feeding a clustering algorithm.
`SystemLanguageModel` doesn't know the groups it's naming came from cosine
similarity. Making four independent black boxes into one coherent product is
where all the work went — and where all the optimization opportunity turned out
to be.

### What happens when you save a log

One piece of text fans out to three models and lands in three different places
in the UI. Nothing here is sequential except where it has to be:

```
text ─┬─> KeywordNamer → GenAiService.entryKeywords
      │     → Swift entryKeywords / @Generable EntryKeywords
      │           └─> entry.keywords ─────────────────────────► [log card]
      │
      ├─> NLTagger sentiment ──> entry.moodScore ─────────────► [mood dot]
      │
      └─> NLContextualEmbedding ──centred cosine ≥ Otsu──> ThemeCluster
                │                    (provisional label: sentence keywords)
                └─> ClusterNamer.relabelAll
                      → GenAiService.labelThemes
                        → Swift labelThemes / @Generable ThemeNames
                          → applyClusterLabels → cluster.label ► [Analytics]
```

Three properties of this shape are load-bearing:

**The three branches are independent.** Sentiment doesn't wait on embeddings;
keywords don't wait on either. A device where the contextual-embedding assets
never finish downloading still gets a mood dot and card keywords — the entry is
simply stored unclustered. Nothing in the fan-out is a chain.

**The card is written twice, on purpose.** `entry.keywords` gets a synchronous
value the instant the entry is saved, so a log card is never blank; the model's
answer overwrites it when it arrives. Phase 1 of a save cannot wait on an
inference and must not fail with one.

**Theme naming is deferred and global.** A new sentence joining a cluster gives
that cluster a *provisional* label — its own keywords — because a theme with no
name is worse than a theme with a rough one. The real name comes from
`relabelAll`, which renames **every** cluster in a single request, never just
the one that changed. That's not laziness: the model can only make names
distinguish each other if it sees them side by side, and one changed sentence
shifts what is distinctive about every other theme.

The two `@Generable` schemas — `EntryKeywords` and `ThemeNames` — are both flat
`[String]`. `ThemeNames` is matched back to clusters **by position**, and the
cluster ids never leave Swift. Making the model echo an integer it has no reason
to get right costs tokens and risks a hallucinated id silently renaming the
wrong theme.

---

## Optimization work

Mapped to the challenge's criteria. The first three are the substantive ones.

### Model size — 0 MB of weights, and that's the whole point

Froyou bundles **no model files at all**. Not a quantized encoder, not a GloVe
table, not an ONNX runtime. The four models it uses are already on the device,
already shared with every other app, and already paged in by the OS.

Here is the entire release build, measured (`flutter build ios --release`):

| Component | Size | What it is |
|---|---:|---|
| `flutter_assets/fonts` | **21.0 MB** | SF Pro Rounded, four weights |
| `Flutter.framework` | 9.8 MB | the Flutter engine |
| `App` (Dart AOT snapshot) | 6.7 MB | **all of Froyou's own code** |
| `Runner` | 3.8 MB | the three Swift channels + bootstrap |
| `ObjectBox.framework` | 2.7 MB | the on-device vector database |
| `Assets.car` | 1.3 MB | the app icon, 15 sizes |
| everything else | ~0.6 MB | plugin resource bundles |
| **Total `.app`** | **48.3 MB** | |
| **Model weights** | **0 bytes** | |

Reproduce it: `find build/ios/iphoneos/Runner.app -name "*.mlmodelc" -o -name
"*.onnx" -o -name "*.tflite"` returns nothing.

**The largest single asset in this AI app is the typeface.** The four SF Pro
Rounded weights outweigh the Flutter engine, the Dart snapshot, the vector
database and the Swift channels *combined* — and every model in the product is
free. Cutting the fonts would shrink the download by 43%; cutting the AI would
shrink it by 0%.

Compare honestly: a bundled-model app of this shape needs a text encoder
(~50–130 MB at INT8) — larger, on its own, than this entire application — and if
it wants generation, something in the 1–2 GB range. That second number is why
on-device apps that start out wanting a language model almost always abandon it
and fall back to embeddings: the weights are simply too heavy to ship in 2026.
Froyou never had to make that trade, because a 3-billion-parameter model was
already installed on the device. **The generative feature that a bundled-model
app has to give up as too heavy costs Froyou nothing, because Froyou doesn't own
the model.**

The trade is real and stated plainly below: you get Apple's model or none.

### Model quality — the anisotropy fix

**This is the headline, and it's the one that made the app work.**

The naive design is: embed each sentence, cosine-compare it to each theme
centroid, join above a threshold. This does not work, and the failure is
instructive.

Mean-pooled contextual embeddings are **anisotropic** — they occupy a narrow
cone rather than the whole sphere, sharing one large common direction. Measured
on a real device with real journal entries, three sentences about *cooking*, *an
audiobook*, and *a relationship* scored **0.86, 0.91 and 0.94** against the same
cluster. That's a spread of **0.076 across topics with nothing whatsoever in
common** — and everything sits above 0.85. There is no threshold you can put
inside that band. Set it low and every theme merges into one; set it high and
nothing ever joins anything.

The first casualty of this is the obvious optimization. ObjectBox stores the
vectors behind an HNSW index, and the fast path — `nearestNeighborsF32` — is
right there. **It is not used, and cannot be**: the index can only rank *raw*
vectors, and raw vectors are precisely the thing that carries no signal. The
approximate-nearest-neighbour structure everyone reaches for first is the one
piece of machinery this problem rules out.

You cannot fix anisotropy in the model either. You don't own the model. So it's
fixed in the pipeline.

**Centring is the fix.** Subtract the mean of every stored embedding, then
renormalize. What's left is the part that is actually about cooking or a
deadline. The same device data then reads: unrelated pairs at a median of
**−0.036**, related pairs out at **p99 0.513**. That is a usable signal, from a
0.076-wide band that had none.

**The threshold is measured, not chosen — and three plausible choices all failed
first.** Each is recorded because each looked right:

| Value | Where it came from | How it failed |
|---|---|---|
| **0.55** | the synthetic seed, where same-topic vectors share an axis and score 0.88 | 26 sentences → **25 themes** |
| **4/√512 ≈ 0.177** | the noise floor — four sigma past chance, and mathematically defensible | sat **below the user's p90**; put an audiobook in with work |
| **p90** | "the top tenth of pairs are related" | the seed's is a *fifth* — broke the seed |

The 4σ noise floor is the instructive failure: it is the answer the geometry
suggests, it is provably beyond chance, and it is still wrong, because "beyond
chance" and "about the same subject" are not the same question.

**What works is Otsu's method** — the thresholding algorithm from image
binarization, run over the pairwise similarity distribution. Those scores are
two overlapping piles: near-zero for sentences that merely share a language,
higher for ones that share a subject. Otsu finds the valley between them by
maximising between-group variance, and it assumes nothing about where the cut
sits or how many pairs fall either side — which is exactly why it survives both
a real journal and a synthetic seed whose distributions have different shapes.
On the seed it picks **0.333**, captures exactly the **13 same-topic pairs out
of 66**, and rebuilds exactly the **4 seeded topics**. The 4σ noise floor stays
in the code as a *floor* only, so a genuinely varied journal still cannot
collapse into one theme.

That is a model-quality improvement for a fixed model size — arrived at from the
only direction available when the weights aren't yours.

**Incremental assignment cannot stand alone.** Two problems compound: the mean
is only estimable once there is text, so the earliest sentences are placed with
the measure that doesn't work and nothing revisits them; and a centroid drifts
as it absorbs members, so what a cluster accepts depends on arrival order. A
theme that has swallowed everything becomes a magnet and never comes apart.
`reclusterAll` regroups every sentence from scratch, oldest first.

**But not on every save** — and this is where the correctness fix had to be
paid for. `maybeRecluster` rebuilds once per launch, then only when the corpus
has grown by half again, or when the mean has actually drifted
(`_meanStability`). The mean converges quickly, and a full rebuild only earns
its cost when the thing every comparison is *relative to* has moved.

**The corpus mean comes from the clusters, not the sentences.** This was the
single most expensive thing in the pipeline before it was fixed. Centring needs
the mean of every clustered sentence, and computing it directly means loading
thousands of sentences and their 512-float embeddings on every save. Instead
each cluster carries a `sumVector`, so summing *tens of clusters* gives exactly
the same mean — not an approximation of it — for a fraction of the I/O.

Two supporting decisions:

- **Sentences are embedded independently**, never as one paragraph.
  `NLContextualEmbedding` is contextual, so embedding a paragraph in one pass
  makes the same sentence produce different vectors depending on its neighbours
  — which silently poisons cross-entry similarity. Isolating each sentence keeps
  sentence → vector a pure function.
- **Vectors are normalized at the source** (`normalize: true` on the native
  side). This isn't cosmetic: the centroid is a running raw sum, so
  unnormalized vectors would let long sentences dominate it. It also means the
  stored dot product *is* the cosine — no magnitudes computed at query time.

All of it is inspectable at runtime. `[Cluster]` in the console prints the
per-sentence decision, the pairwise distribution with the chosen threshold and
**which rule set it**, and whether a rebuild happened. A clustering system whose
threshold moves per corpus is untunable without that line.

### Model speed, latency and energy

**Perceived save latency is decoupled from inference entirely.** The save
pipeline has two phases and phase 1 never depends on phase 2. Raw text is
committed synchronously to ObjectBox and the UI updates; sentiment, embeddings,
clustering and naming run unawaited afterwards with a 30-second budget. Time to
"my words are safe" is a local write. Inference latency is invisible.

**Round-trips are batched, everywhere it matters.**

- `embedSentences` splits *and* embeds natively in **one channel crossing
  instead of N+1**, and detects the language once over the whole text rather
  than per sentence — detection on a single short sentence is unreliable, so
  this is a quality win as well as a latency one.
- Mean-pooling happens **in Swift**, over the raw result. The channel carries
  512 doubles per sentence, not `tokens × 512`.
- **All clusters are named in a single generation request**, never one per
  cluster. This is both faster and *better*: the model can only make names
  distinguish each other if it sees them side by side.
- `NLContextualEmbedding` instances are **cached per language** in the channel —
  loading one is expensive and the language rarely changes.

**Guided generation is used as a decode-time optimization, not just an API.**
`@Generable` + `@Guide` constrain the model's output to a schema, which removes
the parse-retry loop entirely. The schemas are also shaped to minimize
generated tokens: `ThemeNames` is a flat `[String]` matched back **by position**
rather than a list of `{id, label}` pairs, because making the model echo an
integer it has no reason to get right costs tokens *and* risks a hallucinated id
silently naming the wrong theme. The ids never leave Swift.

**A failure latch protects the battery from a doomed inference.**
`SystemLanguageModel` reporting `.available` is necessary but not sufficient —
generation additionally needs Apple's safety classifier, and where that asset is
missing every call fails while the model is still advertised as present.
`GenAiService` counts consecutive generation failures and after **two** stops
asking for the rest of the session. Without it, a device in that state pays a
full failed inference on every single save, forever.

**The largest energy win in the app had nothing to do with AI.** Home used to
have a slow Ken Burns drift on the backdrop — a transform above a
`RepaintBoundary`, which should be compositor-only and free. It was the single
most expensive thing in the app. A raster cache will not hold a layer whose
transform changes every frame, so the entire `EdgeGlowImage` — **two-pass
Gaussian included — was re-rendered at full DPR on every frame Home was
idle**, and the photo was resampled each frame, which read as shimmer on fine
detail. Deleting the drift made idle Home actually idle. The lesson generalized
into a rule the codebase now follows: *animate a cached subtree, don't repaint
one.* `LivingBackdrop` paints each blob behind its own boundary and hands it to
`AnimatedBuilder` as `child`, so a frame costs three transform matrices instead
of three full-screen gradient fills. The blur shader is compiled at boot rather
than on first frame, so Home never renders unblurred and snaps.

### Developer experience

- **190 tests across 21 files**, including golden tests for every one of the
  five Home layouts in both brightnesses.
- **A channel test harness that ships in release.** Long-press the version
  label → `ChannelTestView` drives `app/speech`, `app/nlp` and `app/genai`
  directly on a physical device. When on-device output looks wrong, this is what
  tells you whether the problem is the channel or the app — and it has to ship in
  release because the model is only real on a signed build on real hardware.
- **`--dart-define=SEED_DEMO=true`** seeds 12 believable clustered logs, because
  clustering has nothing to say until there are a few dozen sentences and typing
  those by hand to demo the app is not a good use of anyone's time.
- **One boot line that answers the only question that matters:**
  `[boot] genai available=true`. Whether a theme was named by the language model
  or the statistical fallback is invisible from the UI by design, which makes
  "the labels look worse than I remember" undiagnosable without it.
- **A contrast test that walks every preset × brightness × tint combination**
  and asserts body text clears 4.5:1. No colour in this codebase is derived by
  hand.
- **The app icon is generated from vector, not drawn.** `assets/brand/app-icon.svg`
  → `./tool/render_icon.sh` → all fifteen PNGs. Only the 1024 comes from vector;
  the rest are Lanczos downsamples, because re-rendering the SVG at 40 px puts
  the bezel highlight and the turbulence field below a pixel each and simply
  drops them.

### Arm-specific

Every inference in Froyou runs on Apple silicon — an Arm CPU with an Arm-designed
Neural Engine — through Apple's own frameworks, which means it is scheduled onto
the ANE and the performance cores by code that knows the hardware better than we
ever could. The Arm-specific optimization work here is **not writing kernels; it
is arranging the app so Apple's kernels are used well**: batching to reduce
crossings into them, caching model instances so they aren't reloaded, keeping
every unit of work off the platform thread, latching off inference that is going
to fail, and eliminating the GPU work that was quietly costing more than all the
inference combined.

The GPU side is Arm-specific in a way that's easy to miss: Apple's GPU is
tile-based deferred, and the raster-cache behaviour that made the Ken Burns
regression so expensive is a direct consequence of that architecture. The fix —
hold the expensive layer still, animate the cheap transform above it — is a
tile-based-renderer optimization, not a general one.

---

## Platform limitations we had to design around

Being honest about these is the price of the strategy.

**Availability is a hardware-and-settings question, not an OS-version one.** The
deployment target is iOS 26 and that guarantees nothing. `SystemLanguageModel`
is absent on devices without the neural capacity for Apple Intelligence, absent
when the user has it switched off, and absent while assets download. Those three
demand *different product responses*, so they're distinct values in a Dart enum:
`deviceNotEligible` is permanent and should never be mentioned to the user;
`appleIntelligenceNotEnabled` is a setting they control; `modelNotReady` is
temporary and worth retrying.

**`.available` is necessary but not sufficient.** In the Simulator the model
reports itself available and generation still fails —
`SensitiveContentAnalysisML Code=15 → ModelManagerError 1026`, Apple's safety
classifier, which isn't provisioned there. **Real model output can only be
verified on a physical A17 Pro or newer device.** That single fact shapes the
whole test strategy: everything on the model path needs a mock, and the channel
harness has to ship in release.

**You cannot fine-tune, quantize, or swap.** No LoRA, no distillation, no
INT4, no measuring tokens/sec against an alternative. The entire lever is what
you do around the model — which is precisely why the anisotropy fix exists.

**`NLContextualEmbedding` downloads its assets on first use, per language.**
The first save on a fresh device can be slow, and on a device that never
completes the download the app must still work. It does: sentiment and keywords
run independently of the embedding pass, sentences are stored unclustered, and
themes simply don't form.

**The models are iOS-only by construction.** There is no portable equivalent of
this app, and that's a deliberate trade, not an oversight.

**So every model path in Froyou has a floor:**

| Model path | Falls back to |
|---|---|
| Theme names (`SystemLanguageModel`) | class-based TF-IDF (`ClusterLabeler`) |
| Entry keywords (`SystemLanguageModel`) | frequency + phrase bonus |
| Speech transcription | typing |
| Embeddings / clustering | entry saved unclustered; sentiment still runs |
| Follow-up question | **nothing** — no question appears, on purpose |

The statistical floor isn't a stub. `ClusterLabeler` uses **class-based TF-IDF**,
the scoring BERTopic introduced for exactly this job: collapse each cluster into
one document, weight each term by how much it distinguishes that cluster from
the others. Plain within-cluster frequency cannot do this — if you journal about
work every day, "work" is the most frequent word in the sleep cluster and the
family cluster too, and every theme ends up named after it. It scores adjacent
word pairs alongside single words with a phrase bonus, because "deadline moved"
says something that "deadline" and "moved" ranked separately do not.

---

## The advantage: the app improves on Apple's release schedule

This is the argument for the whole strategy.

Every optimization in a bundled-model app is a one-time purchase that starts
depreciating the moment you ship. Your INT8 encoder is as good as it will ever
be. Improving it means picking a new model, re-quantizing, re-validating, and
pushing a release — and paying for the extra megabytes.

Froyou's model layer is a **subscription to Apple's roadmap**, paid in lock-in.
When iOS 27 ships a `SpeechTranscriber` that handles disfluency better, every
Froyou install transcribes better. When `SystemLanguageModel` gets sharper,
every theme name gets sharper. When `NLContextualEmbedding` becomes less
anisotropic, the centring step keeps working and the clusters get cleaner. When
Apple Intelligence reaches more devices, more users cross from the statistical
tier into the model tier — silently, because the app was built expecting that
crossing to happen in both directions.

And it compounds with the Arm story specifically. Apple ships a new Neural
Engine roughly annually. An app that owns its model gets that speedup only for
whatever its own runtime can exploit. An app that calls the system model gets it
in full, because Apple reschedules its own inference onto the new hardware as a
matter of course.

The right way to state the trade: **we gave up control of the model to get
compounding returns on it.** For a journal that has to be free, private, small,
and still working in three years, that's the correct side of the trade — and
because every path has a floor, the day Apple's model *isn't* there, the app
still works.

---

## Challenges we ran into

**Cosine similarity didn't work, and it took a while to believe it.** Everything
scored 0.86–0.94 against everything. The instinct is to tune the threshold; the
reality is that no threshold exists inside a 0.076-wide band. Understanding
*why* — anisotropy in mean-pooled contextual embeddings — was the turning point
of the project.

**Then the threshold ate another three attempts.** Centring gave us a real
signal; it did not tell us where to cut. A value tuned on the synthetic seed
turned 26 sentences into 25 themes. The noise floor at 4/√512 — defensible,
provably beyond chance, the answer the mathematics hands you — sat below the
real user's p90 and filed an audiobook under work. The p90 itself broke the
seed, whose related-pair share is a fifth rather than a tenth. Every one of the
three was principled and every one was wrong, because each assumed something
about the *shape* of the distribution. Otsu's method assumes nothing, and works
on both. That sequence — three defensible constants, all wrong, replaced by one
algorithm that reads the data — is the piece of work most worth stealing from
this repo.

**A model that reports itself available and then fails every call.** Debugging
the Simulator's `SensitiveContentAnalysisML` failure cost real time, and the
lesson — availability is not a promise about generation — is now encoded as the
failure latch.

**A performance regression that looked free.** The Ken Burns drift was a
transform over a `RepaintBoundary`. Every mental model said compositor-only. It
was the most expensive thing in the app, and finding it required disbelieving
the abstraction.

**Timezone-correct reminders are a trap.** The `timezone` package ships the
zone database but cannot tell where the device is, so `tz.local` stays UTC until
something sets it — and a 21:00 reminder then fires at 21:00 **UTC**. That is
plausible enough to ship and only detectable by *waiting*. `flutter_timezone`
supplies the IANA name; if it fails, `ReminderService` reports itself unready
and reminders switch off rather than firing at the wrong hour. Wrong-hour is
worse than off for an app whose whole premise is showing up at the right moment.

**Testing an app built on models that don't exist in CI.** Anything that saves
a log reaches the namer, which asks the model if it's available; unmocked, that
call never completes under the fake clock and the test hangs to its timeout.
This once turned an 80-second suite into twenty minutes. The speech version is
nastier — recording *looks* like it started, and Stop silently does nothing.
Both now have first-class mocks and both are documented as landmines.

**Writing an app about anxiety without being annoying about it.** Every check-in
rule in `FollowUpService` is a restraint: only the day after, never in the
moment. Only on the day's average, never on one low entry. Cleared the moment
you log. No question at all rather than a canned one. The hard part of this
product was deciding what it should *not* do.

---

## Accomplishments we're proud of

**Generative theme naming on a phone, at zero bundle cost.** The thing a
bundled-model app of this shape has to give up as too heavy, Froyou does — in a
48.3 MB app that is smaller than the text encoder alone would have been, by not
owning the model.

**A model-quality fix on a model we don't control.** From an unusable 0.076-wide
similarity band — every topic scoring 0.86–0.94 against every other — to
unrelated pairs at a median of −0.036 and related pairs out at p99 0.513,
achieved entirely in the pipeline. This is the part that generalizes: anyone
using pooled contextual embeddings for similarity is sitting on the same
problem, probably without knowing it.

**Total offline operation as a structural property.** Not a toggle, not a
promise — there is no network code to audit. Airplane mode changes nothing.

**Three graceful-degradation tiers that are invisible from the UI.** The same
build is coherent on an A17 Pro with Apple Intelligence on, on an older iOS 26
device, and in a Simulator where generation is impossible. You cannot tell from
looking which tier you're in — only the boot log knows.

**An interface you're glad to open.** Your own photos, blurred and glowing at
the edges so they dissolve into the page; a caption you wrote; SF Pro Rounded
with a type scale where tracking actually goes negative above body size; a
living gradient wash behind everything. 190 tests, golden-covered, contrast-
verified at 4.5:1 across every preset × brightness × tint combination. It is a
journalling app that does not look like a form.

---

## What we learned

**The best mobile-AI optimization available today is often not shipping a
model.** Everyone benchmarks tokens/sec. Nobody benchmarks the 500 MB download
that made a user abandon the install. Platform models are a real and badly
under-used strategy — and on Arm specifically, they're the only way to get the
vendor's own ANE scheduling for free.

**Embeddings are geometry, and the geometry is not what you assume.** "Cosine
similarity" sounds like a solved primitive. It isn't. Anisotropy is a property
of every pooled contextual embedding model and it silently destroys threshold-
based systems. Centre your vectors before you compare them.

**A defensible constant is still a constant.** Every threshold we derived from
first principles — from the seed, from the dimensionality, from the percentile —
was wrong on some corpus, because each one quietly assumed the shape of a
distribution it had never seen. The thing that worked was refusing to pick a
number at all and letting an algorithm read the valley out of the data on every
pass. If a constant in your pipeline was arrived at by reasoning rather than by
measurement, it is probably fitted to the one dataset you had in front of you.

**Availability is a spectrum, not a boolean.** Four distinct unavailability
reasons demanding four different product responses, plus one state where the
model claims to be there and isn't. Designing for that is most of the work of
building on a platform model.

**Not shipping the model means shipping everything else twice.** Every model
path needed a real fallback, and "real" means the statistical floor is good
enough to ship on its own. c-TF-IDF isn't a stub — it's a second product.

**The expensive frame is rarely where you think.** The most costly thing in an
AI app turned out to be a photo gently drifting.

**Restraint is the feature.** In a mental-health context, the design work is
mostly deciding what not to do. No auto-detected distortions. No streaks. No
score. No question at all rather than a canned one.

---

## What's next

**CBT structure on top of the logs.** Cognitive Behavioural Therapy has a
vocabulary for exactly what Froyou already finds — catastrophizing, mind-reading,
all-or-nothing thinking — and the clustering machinery is already grouping
entries by the shape of the thought. The next step is tagging logs against that
framework and naming the feeling underneath, so a theme isn't just "the
conversation I keep not having" but "the conversation I keep not having ·
mind-reading · anxious." Non-negotiable constraint: **this stays self-tagged and
suggested, never asserted.** An app telling someone they're catastrophizing is
not a thing we'll ship. Offering the word, and letting them decide whether it
fits, is.

**Enhanced transcription.** Speaker-aware segmentation, better handling of
disfluency and self-correction, punctuation restoration, and custom vocabulary
for the names and places that recur in someone's own life. Much of this arrives
for free as `SpeechTranscriber` improves — which is exactly the compounding
return the platform-model strategy was chosen for.

**Multimedia notes.** Voice memos kept as audio alongside their transcript;
photos attached to an entry and understood with the Vision framework; a sketch
or a screenshot as the body of a log. All of it embedded into the same 512-dim
space so a photo can join a theme the way a sentence does.

**Import from other sources.** Apple Notes, Day One, Journal, plain markdown,
and Apple Health's State of Mind. Someone with three years of journalling
elsewhere should be able to point Froyou at it and immediately see the loops —
that's the moment the product is most convincing, and right now it takes a month
of use to reach it. Import runs entirely on-device, like everything else.

**Better analytics.** Themes over months rather than one week. Which themes are
cooling and which are heating. Time-of-day and day-of-week structure. Mood
trajectory *within* a theme rather than overall — "this got easier" is a more
useful sentence than "you were sad on Tuesday." Correlation between themes that
co-occur. All of it built on the same rule the current analytics follows: every
claim about your week is backed by the sentences that produced it, one tap away.

---

## Functionality / Output

The output is **a working iOS 26 application** — an installable IPA and the full
open-source repository that builds it.

Concretely, the app produces:

- **A local journal.** Text or streamed on-device transcription, stored in
  ObjectBox on the device and nowhere else.
- **A 512-dimensional vector per sentence**, from `NLContextualEmbedding`,
  stored in ObjectBox and compared on *centred* cosine.
- **A live set of named themes** — groups over every sentence ever written,
  rebuilt from scratch when the corpus grows or its mean drifts, named by
  `SystemLanguageModel`.
- **A weekly analytics view** — themes recurring more than once in seven days,
  with entry counts, the medoid sentence, and the supporting sentences behind
  each count.
- **A daily check-in** — a model-written question the morning after a hard day,
  or a scheduled local notification with a model-written line.
- **Zero network traffic.** Verifiable by running it in airplane mode, or by
  grepping the repository for a network call.

Also in the repo, as engineering output: three documented Flutter↔Swift channels
over Apple's speech, NLP and generative frameworks that are reusable
independently of this app; the anisotropy-corrected clustering implementation;
190 tests including golden coverage of five layouts; and a vector→raster app
icon pipeline.

---

## Setup Instructions

Full detail — including the unsigned-IPA route, the capability tiers, and a
troubleshooting table — is in **[`README.md`](../README.md)**. The short version:

### Requirements

- macOS with **Xcode 26.0+** (the iOS 26 SDK — `SpeechTranscriber`,
  `NLContextualEmbedding` and `FoundationModels` don't exist in earlier SDKs)
- **Flutter 3.44.8** stable (Dart 3.12.2)
- CocoaPods 1.16.2+
- An iPhone on **iOS 26.0+**. For the generative path, an **A17 Pro or newer**
  with Apple Intelligence enabled.

### Build and run

```bash
git clone <repo-url> froyou && cd froyou
flutter pub get

flutter run                                  # booted iOS 26 simulator or device
flutter run --dart-define=SEED_DEMO=true     # + 12 believable clustered logs
```

ObjectBox bindings are checked in, so a fresh clone needs no codegen.

### Validate

```bash
flutter analyze     # must be clean
flutter test        # 190 tests, ~110s
```

### Build an IPA

Set your own Team and bundle identifier in `ios/Runner.xcworkspace` first — the
repo ships `com.example.froyou` and the author's team, and both will fail for
you.

```bash
flutter build ipa --export-method development
# → build/ios/ipa/*.ipa
```

No Apple Developer account? Build unsigned and package it yourself:

```bash
flutter build ios --release --no-codesign
cd build/ios/iphoneos && mkdir -p Payload && cp -R Runner.app Payload/ \
  && zip -qr ../../../froyou-unsigned.ipa Payload && rm -rf Payload && cd ../../..
```

### Confirm which tier you're on

The one line that matters, in the debug console at launch:

```
[boot] genai available=true
[boot] genai available=false reason=deviceNotEligible
```

`true` means themes are named by `SystemLanguageModel` and the follow-up question
can appear. `false` means the class-based TF-IDF fallback is naming them and no
question will appear — the app is fully functional either way, which is the
point. In the Simulator this will report `true` and generation will still fail;
see the limitations section above.

To exercise the three native channels directly on a device: **Settings →
long-press the version label → Channel test**. It ships in release, because the
model is only real on a signed build on real hardware.

---

## License

MIT — see [`LICENSE`](../LICENSE).
