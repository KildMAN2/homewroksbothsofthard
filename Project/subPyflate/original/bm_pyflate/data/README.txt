Data file: interpreter.tar.bz2

This is the bzip2-compressed workload shipped with the pyperformance
bm_pyflate benchmark. It is NOT included in this repository because it
is a binary that also ships with the installed pyperformance package.

To reproduce measurements, use the file that ships with your installed
pyperformance:

  find /usr/local/lib/python3.10/dist-packages/pyperformance \
       -name interpreter.tar.bz2

or, on the VM, run:

  python3 -c "import pyperformance, os, pathlib; \
              p = pathlib.Path(pyperformance.__file__).parent / \
                  'data-files/benchmarks/bm_pyflate/data/interpreter.tar.bz2'; \
              print(p, p.exists())"

The benchmark's internal MD5 check
(afa004a630fe072901b1d9628b960974) verifies that decompression produced
the correct output regardless of which pyperformance copy provided the
file.
