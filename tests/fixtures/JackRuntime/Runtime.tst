load,
output-file Runtime.out,
compare-to Runtime.cmp,
output-list RAM[5]%D1.6.1;
repeat 10000000 { vmstep; }
output;
