/// Which part of the chart is on screen.
///
/// A chart holds more than fits on one scroll, and the previous single column
/// meant the visit history — the thing most often wanted — was always at the
/// bottom past six other panels. Splitting it costs one tap and saves the
/// scroll; the split is by *question being asked*, not by data type:
///
/// * **Summary** — "what do I need to know before I walk in?"
/// * **History** — "what happened last time, and the time before?"
/// * **Observations** — "which way is this going?"
/// * **Files** — "where is the X-ray?"
enum ChartSection { summary, history, observations, files }
