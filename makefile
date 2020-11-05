tangled: pipetangled.v assembly
	iverilog -o pipetangled Tangled_v2.v
	vvp pipetangled

dump: dump.txt
	gtkwave dump.txt

assembly: tangled.aik testAssembly #branchTest memoryTest
	./aik tangled.aik testAssembly

clean:
	rm *.text *.data tangled
