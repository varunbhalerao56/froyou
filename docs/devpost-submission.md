# Froyou

**Arm AI Optimization Challenge 2026 — Track 3: Mobile AI**

A local-first iOS journal that notices what you keep coming back to. You talk or
type; it transcribes, reads the mood, embeds every sentence, groups those
embeddings across everything you've ever written, and names the groups — so it
can tell you that six logs written six different ways, with no word in common,
were all the same worry.

It runs four separate on-device models on the Arm silicon already in your phone,
and ships **zero bytes of model weights** to do it — in a 48.3 MB app whose
largest single asset is the font. There is no server, no account, and no network
call anywhere in it.

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

Three things followed from that:

**It had to be simple to the point of being boring.** Every journalling app I
tried wanted me to pick a mood emoji, choose a prompt, tag the entry, rate my
sleep. When you're already stuck in a loop, a form is another loop. Froyou has
one text field and a microphone button.

**It had to check on me.** Not a generic 9 p.m. "time to journal!" push — a
question that knows what yesterday was like. If yesterday averaged out rough,
the next morning asks something specific and warm, written from the themes I
actually touched. If yesterday was fine, it doesn't bring it up. And the moment
I log today, the question clears, because it's done its job.

**It had to be comforting to open.** The home screen is your own photos —
whatever you want to be reminded matters — drifting behind a caption you wrote,
blurred and glowing at the edges so it dissolves into the page rather than sits
on it. Not a dashboard. Not a streak counter. A thing you're glad to look at.

---

## What it does

**Talk or type.** Recording streams live from iOS 26's `SpeechTranscriber`, with
each word fading in as it lands and quietly revising itself when the recognizer
changes its mind. Or just type. The compose view clears the whole screen so
there's nothing but the words.

**It finds the loops.** Every sentence becomes a 512-dimensional
`NLContextualEmbedding` vector, stored in ObjectBox. Those vectors are grouped
by similarity against a threshold the app derives from your own writing, and the
whole corpus is regrouped from scratch whenever it has grown or shifted enough
to be worth it. Each group gets a name from Apple's on-device language model.
"Deadline moved." "Not sleeping." "The conversation I keep not having."

**It shows you the week.** After five logs, an analytics view lists the themes
that came up more than once in the last seven days: the name, how many separate
entries touched it, the sentence of yours that sits closest to the group's
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

The same question can also come to you. **Morning follow-up** is a second
notification with its own time — 9:00 AM by default, against the evening nudge's
9:00 PM — carrying the question itself as the notification body, so a hard day
gets answered the next morning whether or not you think to open the app. It has
its own notification id so the two schedule and cancel independently, but it
rides on reminders being on: one permission, one thing you think of as
"notifications". Unlike the nightly nudge it does **not** repeat — it's about
one particular day, so it fires once and the next save arms the next one.

**It stays yours.** Airplane mode changes nothing. There is no account, no sync,
no telemetry, and no network code to audit — the promise is structural, not a
setting.

---

## How we built it

**The strategy is: rent the models, own the pipeline.**

The conventional way to build a private on-device AI app is to bundle quantized
models — a text encoder, maybe a vision encoder, a word-vector table — and then
spend the project fighting to keep the download under half a gigabyte. Froyou
takes the opposite bet. iOS 26 ships `SpeechTranscriber`, `NLTagger`,
`NLContextualEmbedding` and `SystemLanguageModel` as system services, all
compiled for the Arm CPU and Neural Engine, and all resident once for every app
on the device. Using them means the marginal on-disk cost of the AI is **0 MB**,
the marginal memory cost is shared with the OS, and the inference path is
Apple's own — already scheduled onto the ANE and the performance cores by code
that knows the hardware far better than we could.

The cost is real and it shapes everything below: **you cannot fine-tune,
quantize, swap, or even properly profile a model you don't own.** Every
optimization has to happen upstream or downstream of it.

Four Apple frameworks that were never designed to work together, across three
native channels:

| Channel | Framework | What it does here |
|---|---|---|
| `app/speech` | `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26) | Streaming transcription with live revision. EventChannel for the stream, MethodChannel for control — the split is deliberate. |
| `app/nlp` | `NLTokenizer`, `NLTagger`, `NLContextualEmbedding` | Sentence splitting, sentiment, 512-dim contextual embeddings, mean-pooled natively. |
| `app/genai` | `SystemLanguageModel` (Foundation Models) | Theme names, entry keywords, the follow-up question, the reminder line — all via `@Generable` guided generation. |
| — | ObjectBox | On-device store for 512-dim vectors. An HNSW index is declared but deliberately **not** used for grouping — see Challenges. |

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

**Theme naming is deferred and global.** A new sentence joining a group gives it
a *provisional* label — its own keywords — because a theme with no name is worse
than a theme with a rough one. The real name comes from `relabelAll`, which
renames **every** group in a single request, never just the one that changed.
That's not laziness: the model can only make names distinguish each other if it
sees them side by side, and one changed sentence shifts what is distinctive
about every other theme.

### Zero bundled weights

Froyou bundles **no model files at all**. Not a quantized encoder, not a GloVe
table, not an ONNX runtime. Here is the entire release build, measured with
`flutter build ios --release`:

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

**The largest single asset in this AI app is the typeface.** The four SF Pro
Rounded weights outweigh the Flutter engine, the Dart snapshot, the vector
database and the Swift channels *combined* — and every model in the product is
free. Cutting the fonts would shrink the download by 43%; cutting the AI would
shrink it by 0%.

For comparison: a bundled-model app of this shape needs a text encoder
(~50–130 MB at INT8) — larger, on its own, than this entire application — and if
it wants generation, something in the 1–2 GB range. That second number is why
on-device apps that start out wanting a language model almost always abandon it
and fall back to embeddings. Froyou never had to make that trade, because a
3-billion-parameter model was already installed on the device.

### How the grouping actually works

The short version; the long version, including everything that failed first, is
in Challenges.

Sentences are grouped on **centred** cosine similarity — the average direction
of all stored embeddings is subtracted before any comparison, because raw
embeddings all point roughly the same way regardless of meaning. The join
threshold isn't a constant: **Otsu's method** reads it off the pairwise
similarity distribution on every pass, with a 4/√512 noise floor underneath so a
genuinely varied journal can't collapse into one theme.

Grouping is redone from scratch rather than patched, because incremental
assignment is order-dependent — a theme drifts as it absorbs sentences, and one
that has swallowed everything becomes a magnet that never comes apart.
`reclusterAll` regroups every sentence oldest-first. **But not on every save:**
`maybeRecluster` rebuilds once per launch, then only when the corpus has grown
by half again or the average has actually moved. A full rebuild only earns its
cost when the thing every comparison is *relative to* has shifted.

**And that average comes from the themes, not the sentences** — the single most
expensive thing in the pipeline before it was fixed. Computing it directly means
loading thousands of sentences and their 512 floats each, on every save. Instead
each theme carries a running `sumVector`, so adding up *tens of themes* gives
exactly the same answer — not an approximation — for a fraction of the I/O.

### Speed, latency and energy

**Perceived save latency is decoupled from inference entirely.** The save
pipeline has two phases and phase 1 never depends on phase 2. Raw text is
committed synchronously to ObjectBox and the UI updates; sentiment, embeddings,
clustering and naming run unawaited afterwards with a 30-second budget. Time to
"my words are safe" is a local write. Inference latency is invisible.

**Round-trips are batched, everywhere it matters.**

- `embedSentences` splits *and* embeds natively in **one channel crossing
  instead of N+1**, and detects the language once over the whole text rather
  than per sentence — detection on a single short sentence is unreliable, so
  this is a quality win as well as a latency one. Each sentence is still
  embedded *separately* inside that one call: the model is contextual, so
  embedding a paragraph in one pass would make the same sentence produce
  different vectors depending on its neighbours, quietly poisoning every
  cross-entry comparison.
- Mean-pooling happens **in Swift**, over the raw result. The channel carries
  512 doubles per sentence, not `tokens × 512`.
- **All themes are named in a single generation request**, never one per theme.
  Faster, and better for the reason above.
- `NLContextualEmbedding` instances are **cached per language** in the channel —
  loading one is expensive and the language rarely changes.

**Guided generation is used as a decode-time optimization, not just an API.**
`@Generable` + `@Guide` constrain the model's output to a schema, which removes
the parse-retry loop entirely. The schemas are also shaped to minimize generated
tokens: `ThemeNames` is a flat `[String]` matched back **by position** rather
than a list of `{id, label}` pairs, because making the model echo an integer it
has no reason to get right costs tokens *and* risks a hallucinated id silently
renaming the wrong theme. The ids never leave Swift.

**A failure latch protects the battery from a doomed inference.**
`SystemLanguageModel` reporting `.available` is necessary but not sufficient —
generation additionally needs Apple's safety classifier, and where that asset is
missing every call fails while the model is still advertised as present.
`GenAiService` counts consecutive generation failures and after **two** stops
asking for the rest of the session. Without it, a device in that state pays a
full failed inference on every single save, forever.

**The largest energy win in the app had nothing to do with AI** — see the Ken
Burns regression in Challenges.

### Designing for a model that might not be there

**Availability is a hardware-and-settings question, not an OS-version one.** The
deployment target is iOS 26 and that guarantees nothing. `SystemLanguageModel`
is absent on devices without the neural capacity for Apple Intelligence, absent
when the user has it switched off, and absent while assets download. Those three
demand *different product responses*, so they're distinct values in a Dart enum:
`deviceNotEligible` is permanent and should never be mentioned to the user;
`appleIntelligenceNotEnabled` is a setting they control; `modelNotReady` is
temporary and worth retrying.

**`NLContextualEmbedding` downloads its assets on first use, per language.** The
first save on a fresh device can be slow, and on a device that never completes
the download the app must still work. It does: sentiment and keywords run
independently of the embedding pass, sentences are stored unclustered, and
themes simply don't form.

**A notification's text has to exist before the moment it's about.** iOS wants
the body at *scheduling* time, and nothing of ours runs when the notification
actually fires — there is no hook to generate a line at 9 AM. So the morning
question cannot be written in the morning. It's composed at the end of a save,
which is the only moment the day's mood and themes are known and the model is
warm. Two consequences, both visible behaviour rather than implementation
trivia:

- **The armed question is about the day your last log belongs to.** Write again
  later that day and it's rewritten against the fuller picture. The notification
  you'd have received at lunchtime is not the one that arrives.
- **No logs, no sentiment, or the model declining ⇒ nothing is sent.** Not a
  generic nudge in the question's place. A warm open question about a day you
  didn't have is worse than silence, and this is the one path in the app with no
  statistical floor underneath it on purpose.

**So every model path has a floor:**

| Model path | Falls back to |
|---|---|
| Theme names | class-based TF-IDF (`ClusterLabeler`) |
| Entry keywords | frequency + phrase bonus |
| Speech transcription | typing |
| Embeddings / grouping | entry saved unclustered; sentiment still runs |
| Follow-up question | **nothing** — no question appears, on purpose |

The statistical floor isn't a stub, even though it isn't a peer either.
`ClusterLabeler` uses class-based TF-IDF, the scoring BERTopic introduced for
exactly this job: collapse each group into one document, weight each term by how
much it distinguishes that group from the others. Plain within-group frequency
cannot do this — if you journal about work every day, "work" is the most
frequent word in the sleep group and the family group too. Its job now is to
keep a device without Apple Intelligence looking at a labelled theme instead of
an empty one.

### Why this compounds

Every optimization in a bundled-model app is a one-time purchase that starts
depreciating the moment you ship. Your INT8 encoder is as good as it will ever
be; improving it means picking a new model, re-quantizing, re-validating,
shipping a release, and paying for the extra megabytes.

Froyou's model layer is a **subscription to Apple's roadmap**, paid in lock-in.
When iOS 27 ships a `SpeechTranscriber` that handles disfluency better, every
install transcribes better. When `SystemLanguageModel` gets sharper, every theme
name gets sharper. When `NLContextualEmbedding` becomes less anisotropic, the
centring step keeps working and the groups get cleaner. When Apple Intelligence
reaches more devices, more users cross from the statistical tier into the model
tier — silently, because the app was built expecting that crossing in both
directions. And Apple ships a new Neural Engine roughly annually; an app that
calls the system model gets that speedup in full.

---

## Challenges we ran into

**Cosine similarity didn't work, and it took a while to believe it.**

An embedding turns a sentence into 512 numbers — effectively a *direction* in
space. Two sentences about the same thing should point the same way, and cosine
similarity measures the angle between them: 1.0 is identical, 0 is unrelated. So
the obvious design is: embed each sentence, compare it to each theme, join
anything above some threshold.

It doesn't work, because of a property called **anisotropy** — the vectors don't
use the whole space. They're crammed into a narrow cone, all pointing roughly
the same way *before* you consider what they actually say. Picture a crowd where
everyone happens to be facing north: watching which way people face tells you
nothing about who's talking to whom.

Measured on a real device, sentences about *cooking*, *an audiobook* and *a
relationship* scored **0.86, 0.91 and 0.94** against the same theme. Three
topics with nothing in common, sitting in a band **0.076 wide**, all above 0.85.
No threshold fits in there. Put it low and everything collapses into one theme;
put it high and nothing ever joins anything.

That also rules out the obvious optimization. ObjectBox stores these vectors
behind an HNSW index and the fast path, `nearestNeighborsF32`, is right there —
but it can only rank *raw* vectors, which are exactly the ones carrying no
signal. The first tool everyone reaches for is the one this problem forbids.

**Centring is the fix.** Work out the average direction of every stored
embedding — the "north" they're all facing — subtract it from each one, and
rescale. What's left is only the part that makes a sentence *different* from
every other sentence: the bit genuinely about cooking, or a deadline. The same
device data then reads unrelated pairs at a median of **−0.036** and related
pairs out at **p99 0.513**. A real signal, out of a band that had none.

**Then the threshold ate three more attempts.** Centring gives you signal; it
doesn't tell you where to cut. Each of these looked right:

| Value | Where it came from | How it failed |
|---|---|---|
| **0.55** | the synthetic seed, where same-topic vectors score 0.88 | 26 sentences → **25 themes** |
| **4/√512 ≈ 0.177** | the noise floor — four sigma past chance, mathematically defensible | sat **below the real user's p90**; filed an audiobook under work |
| **p90** | "the top tenth of pairs are related" | the seed's share is a *fifth* — broke the seed |

The noise floor is the instructive failure: it's the answer the mathematics
hands you, it's provably beyond chance, and it's still wrong — because "beyond
chance" and "about the same subject" are not the same question.

**What works is Otsu's method**, borrowed from image scanning, where it decides
which greys are ink and which are paper. Plot every pairwise similarity and you
get two humps: a big one near zero for sentences that merely share a language,
a smaller one further right for sentences that share a subject. Otsu finds the
dip between them — and assumes nothing about where that dip sits or how big
either hump is, which is why it survives both a real journal and a synthetic
seed whose distributions look nothing alike. On the seed it picks **0.333**,
catches exactly the **13 same-topic pairs out of 66**, and rebuilds exactly the
**4 seeded topics**.

**And then, with the groups finally correct, the names were still wrong.** The
original design had no language model in it at all. Contextual embeddings found
the groups; statistics named them — c-TF-IDF across groups for theme labels,
frequency-plus-phrase-bonus for the words under a log card. It is a genuinely
good algorithm and it produced genuinely useless names, for a reason obvious in
hindsight and invisible while building it: **a statistical extractor can only
ever return terms that literally appear in the text.**

That is precisely the thing this app exists to defeat. The embedding is what
notices that "my manager pushed the date again" and "the timeline slipped"
belong together — different words, one worry. Then the labeler is handed that
correct group and, having only those sentences' own vocabulary to draw on, picks
whichever term is most distinctive and calls the theme *"pushed"* or
*"timeline."* The grouping had solved the synonym problem and the naming
immediately reintroduced it. Every theme name read like a search result for
something you didn't search for.

So the naming layer was rewritten model-first: `SystemLanguageModel` gets the
group's most central sentences and writes a name that need not contain any word
from any of them. The statistics stayed as the floor rather than being deleted —
but the pivot went far enough that there is now a `kModelOnlyLabels` switch,
**currently on**, which turns every statistical fallback off entirely so a blank
keyword line means *the model declined* rather than the statistics quietly
filling in. The fallback being invisible from the UI is normally the point;
while judging naming quality it's the problem.

**A model that reports itself available and then fails every call.** In the
Simulator `SystemLanguageModel` reports `.available` and generation still fails
— `SensitiveContentAnalysisML Code=15 → ModelManagerError 1026`, Apple's safety
classifier, which isn't provisioned there. Debugging that cost real time, and
the lesson — availability is not a promise about generation — is now encoded as
the failure latch. It also means **real model output can only be verified on a
physical A17 Pro or newer device**, which shapes the entire test strategy.

**A performance regression that looked free.** Home used to have a slow Ken
Burns drift on the backdrop — a transform above a `RepaintBoundary`, which every
mental model says is compositor-only and therefore free. It was the most
expensive thing in the app. A raster cache will not hold a layer whose transform
changes every frame, so the entire backdrop — a two-pass Gaussian included — was
re-rendered at full DPR on every frame Home sat *idle*, and the photo was
resampled each frame, which read as shimmer on fine detail. Deleting the drift
made idle Home actually idle. Finding it required disbelieving the abstraction.

**Timezone-correct reminders are a trap.** The `timezone` package ships the zone
database but cannot tell where the device is, so `tz.local` stays UTC until
something sets it — and a 21:00 reminder then fires at 21:00 **UTC**. That is
plausible enough to ship and only detectable by *waiting*. `flutter_timezone`
supplies the IANA name; if it fails, `ReminderService` reports itself unready
and reminders switch off rather than firing at the wrong hour. Wrong-hour is
worse than off for an app whose whole premise is showing up at the right moment.

**Testing an app built on models that don't exist in CI.** Anything that saves a
log reaches the namer, which asks the model if it's available; unmocked, that
call never completes under the fake clock and the test hangs to its timeout.
This once turned an 80-second suite into twenty minutes. The speech version is
nastier — recording *looks* like it started, and Stop silently does nothing.
Both now have first-class mocks and both are documented as landmines.

---

## Accomplishments that we're proud of

**Generative theme naming on a phone, at zero bundle cost.** The feature a
bundled-model app of this shape has to give up as too heavy, Froyou ships — in a
48.3 MB app smaller than the text encoder alone would have been, by not owning
the model.

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
was wrong on some corpus, because each quietly assumed the shape of a
distribution it had never seen. What worked was refusing to pick a number at all
and letting an algorithm read the valley out of the data on every pass. If a
constant in your pipeline was arrived at by reasoning rather than by
measurement, it is probably fitted to the one dataset you had in front of you.

**Grouping and naming are two different jobs.** Embeddings are excellent at
deciding what belongs together and structurally incapable of saying what it is,
because everything they can offer you is a word that was already in the text. We
spent a while trying to do both with one tool, and the tell was that the groups
were right while their names were nonsense.

**Availability is a spectrum, not a boolean.** Four distinct unavailability
reasons demanding four different product responses, plus one state where the
model claims to be there and isn't. Designing for that is most of the work of
building on a platform model.

**The expensive frame is rarely where you think.** The most costly thing in an
AI app turned out to be a photo gently drifting.

**Restraint is the feature.** In a mental-health context, the design work is
mostly deciding what not to do. No auto-detected distortions. No streaks. No
score. No question at all rather than a canned one.

---

## What's next for Froyou

**CBT structure on top of the logs.** Tagging entries against the vocabulary of
Cognitive Behavioural Therapy — catastrophizing, mind-reading, all-or-nothing
thinking — and naming the feeling underneath, so a theme reads "the conversation
I keep not having · mind-reading · anxious." Non-negotiable: **suggested, never
asserted.** An app telling someone they're catastrophizing isn't something we'll
ship. Offering the word and letting them decide whether it fits is.

**Enhanced transcription.** Speaker-aware segmentation, disfluency and
self-correction handling, punctuation restoration, and custom vocabulary for the
names that recur in someone's own life. Most of it arrives free as
`SpeechTranscriber` improves.

**Multimedia notes.** Voice memos kept as audio alongside their transcript,
photos read with the Vision framework, a screenshot as the body of a log — all
embedded into the same 512-dim space, so a photo can join a theme the way a
sentence does.

**Import from other sources.** Apple Notes, Day One, Journal, markdown, Apple
Health's State of Mind. Three years of journalling elsewhere should show you
your loops on day one instead of after a month of use. On-device, like
everything else.

**Better analytics.** Months rather than one week. Which themes are cooling and
which are heating. Mood trajectory *within* a theme rather than overall — "this
got easier" is a more useful sentence than "you were sad on Tuesday."
