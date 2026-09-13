# Original Benchmark perf Profiling

**Project:** subRay HWSW Benchmark Optimization, Analysis, and Hardware Acceleration
**Benchmark:** `raytrace`
**Created:** 2026-09-13
**Status:** Completed
**Deliverable format:** Markdown only (DOCX not required per user decision 2026-09-13)

## Purpose of This Step

This step documents Linux `perf` profiling for the untouched original `raytrace` benchmark. The sampling run was already completed during the baseline step, so this step reuses the existing raw `perf.data` rather than rerunning the profiler.

## What perf Is

`perf` is a Linux performance analysis tool. It can sample where a program spends CPU time and record stack traces so the hot code paths can be analyzed after the run.

## What Sampling Is

Sampling means the profiler interrupts execution at regular intervals and records where the program is currently executing. Repeated samples build an approximate picture of where time is spent, without instrumenting every function call.

## What `-F 999` Means

`-F 999` asks `perf record` to sample at about 999 times per second. A higher sample rate gives more detail but creates more overhead and larger output files.

## What `-g` Means

`-g` enables call-graph recording. Instead of recording only the current instruction or function, `perf` also records the call stack that led there.

## What a Call Graph Is

A call graph shows how execution reached a function. It connects callers to callees so hot paths can be traced through the program rather than looking at isolated functions only.

## Why `python3-dbg` Is Helpful

`python3-dbg` is the CPython debug build. It usually preserves better symbols and stack information, which makes Python-level analysis with `perf` more useful than profiling a stripped or minimally symbolic interpreter.

## What `perf.data` Contains

`perf.data` is the binary output file produced by `perf record`. It contains the recorded performance samples, metadata about the run, and call-stack samples when `-g` is enabled.

## What `perf report` Shows

`perf report` reads `perf.data` and summarizes where samples landed. It can show hot functions, shared libraries or binaries, percentages, and call relationships.

## What Self Time Means

Self time is the fraction of samples attributed directly to a function itself, excluding time spent inside functions it calls.

## What Children / Inclusive Time Means

Children or inclusive time includes samples from a function and the work done underneath it in functions it called. This is useful for identifying hot call paths rather than only leaf functions.

## Verification Before Reuse

Before generating the text report, this step verifies that:

- the benchmark identifier is still `raytrace`,
- the original profiling command used the untouched original benchmark,
- `python3-dbg` was available,
- a successful `perf record` run already produced `perf.data`, and
- the profiling artifacts can be reused without rerunning the sampling step.

## Expected Command

The correct profiling command for this benchmark and environment is:

```bash
perf record -F 999 -g -- python3-dbg -m pyperformance run --bench raytrace
```

The earlier baseline step already ran the equivalent command with an explicit output path for `perf.data`, so this step should not repeat sampling unless verification fails.

## Planned Outputs

- `subRay/profiling/perf.data`
- `subRay/profiling/perf_report.txt`
- `subRay/logs/04_perf_report_stderr.txt`
- `subRay/logs/04_perf_step.txt`

## Verification Results

The previously completed baseline step already established the correct profiling environment and command:

- benchmark identifier: `raytrace`
- Python: `Python 3.10.12`
- debug interpreter: `/usr/bin/python3-dbg`
- pyperformance: `1.14.0`
- perf path: `/usr/bin/perf`
- successful original profiling command:

```bash
perf record -F 999 -g -o /root/homewroksbothsofthard/subRay/results/baseline/perf.data -- python3-dbg -m pyperformance run --bench raytrace
```

The successful baseline stderr confirms that the sampling run completed and produced raw profiling data:

```text
[ perf record: Woken up 438 times to write data ]
[ perf record: Captured and wrote 109.799 MB /root/homewroksbothsofthard/subRay/results/baseline/perf.data (1596484 samples) ]
```

To avoid rerunning profiling, that existing raw profile was reused and copied in the VM to `subRay/profiling/perf.data`.

## Actual Report-Generation Attempts

Attempt 1 from the VM root directory:

```bash
perf report --stdio -i profiling/perf.data > profiling/perf_report.txt 2> logs/04_perf_report_stderr.txt
```

Observed error:

```text
failed to open profiling/perf.dagls: No such file or directory
```

Probable reason:

- the QEMU serial console truncated and merged the command with subsequent terminal input,
- so the `perf.data` path was corrupted before `perf report` actually executed.

Attempt 2 from inside `subRay/profiling`:

```bash
perf report --stdio -i perf.data > perf_report.txt
```

Observed warning after the interrupted VM attempt:

```text
Warning:
Kernel address maps (/proc/{kallsyms,modules}) were restricted.

Check /proc/sys/kernel/kptr_restrict before running 'perf record'.

As no suitable kallsyms nor vmlinux was found, kernel samples can't be resolved.

Samples in kernel modules can't be resolved as well.
```

Probable reason:

- the VM environment restricts kernel symbol maps, which affects kernel-frame resolution,
- and the noisy serial-console workflow again prevented a clean, trustworthy `perf report` capture.

Attempt 3 from inside `subRay/profiling` using a short temporary output name:

```bash
perf report --stdio -i perf.data > r
mv r perf_report.txt
```

Actual outcome:

- this short-file workflow succeeded,
- `subRay/profiling/perf_report.txt` was created in the VM,
- the saved report begins with standard `perf report` header text and sample statistics,
- `perf_port_stderr.txt` contained only:

```text
# To display the perf.data header info, please use --header/--header-only option.
#
```

The first visible lines of the saved report were:

```text
# Total Lost Samples: 0
# Samples: 1M of event 'cpu-clock:pppH'
# Event count (approx.): 1598082080484
#
# Children      Self  Command      Shared Object                              Symbol
	20.63%    20.61%  python       python3.10d
	 5.70%     0.00%  python       [unknown]
	 5.20%     0.00%  python       [unknown]
	 4.49%     0.00%  python       [unknown]
	 4.48%     0.00%  python       [unknown]
	 4.09%     0.00%  python       [unknown]
	 4.02%     0.94%  python       python3.10d
```

Visible child or descendant symbols in the first saved section included:

- `_PyEval_EvalFrameDefault`
- `binary_op1`
- `PyFloat_FromDouble`
- `PyObject_GenericSetAttr`
- `_PyEval_MakeFrameVector`
- `_PyEval_Vector`
- `dict_dealloc.lto_priv.0`
- `lookdict_unicode_nodummy`
- `PyDict_Contains`
- `_PyType_Lookup`
- `get_type_cache.lto_priv.0`
- `_PyFrame_New_NoTrack`
- `_PyObject_GetMethod`

## Result of This Step

- The original benchmark was already profiled successfully during the baseline step.
- Raw profiling data exists and was reused instead of rerunning `perf record`.
- `subRay/profiling/perf.data` was created in the VM workspace by copying the successful baseline `perf.data`.
- After earlier failed attempts caused by VM serial-console truncation, a short-command workflow succeeded and created `subRay/profiling/perf_report.txt` in the VM.
- The report confirms that valid user-space samples were recorded and that Python interpreter and object-operation paths appear prominently in the visible top section.
- Kernel-frame resolution remained limited by VM symbol restrictions, so kernel-related rows may be incomplete or unresolved.
- This step still avoids overclaiming: only the report lines actually observed are summarized here.

## Failure Classification

- **Exact commands:** documented above for all attempts.
- **Exact error in failed attempt:** `failed to open profiling/perf.dagls: No such file or directory`
- **Probable reason for failed attempts:** VM serial-console command truncation/merging.
- **VM/perf/kernel/debug-symbol relation:**
	- primarily a VM serial-console input reliability issue,
	- secondarily a VM/kernel permission or symbol-resolution issue for kernel frames (`kptr_restrict`, kallsyms/vmlinux warnings),
	- not evidence that the user-space `perf record` sampling itself failed,
	- not a `python3-dbg` availability problem, since the baseline run already verified `/usr/bin/python3-dbg` and completed successfully.
	- final `perf report` generation itself did succeed once the command was shortened enough for the VM console to transmit it intact.

## Activity Log

### 2026-09-13 - perf profiling documentation created

**Before action:** Create this Markdown source of truth before running or reusing any profiling command. Prefer reusing the existing `perf.data` from the successful baseline step instead of running `perf record` again.

**Actual outcome:** Verified that the original benchmark had already been profiled successfully during the baseline step and reused that `perf.data` instead of rerunning `perf record`. Two initial `perf report --stdio` attempts in the VM were affected by QEMU serial-console truncation, but a short temporary-output workflow succeeded and produced `subRay/profiling/perf_report.txt` in the VM. The exact commands, earlier failures, and final successful report excerpt are preserved in `subRay/logs/04_perf_step.txt` and `subRay/logs/04_perf_report_stderr.txt`.
