pmjrunner
=========

Poor Man's Job Runner - Provides for the intelligent execution or restart of a sequence of batch programs.

![summary diagram](http://2.bp.blogspot.com/-YCCO8HRVpOg/UGy4mm2tO9I/AAAAAAAAA94/wrCoXs9JLU4/s1600/pmjrunner.gif)

**pmjrunner** is short for Poor Man's Job Runner. It's designed to be used in combination with your OS's default scheduler to provide for the intelligent execution or restart of a sequence of batch programs that have dependencies between them. Used in combination with a tool like SSH, pmjrunner can be used to execute a sequence of batch programs across different nodes and OS's. And yes, it runs great on both Linux and Windows.

For more on how it works, view the comments in pmjrunner.pl (or run it using the -h option). See the README.txt for setup info.