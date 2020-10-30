tangled: pipetangled.v assembly
	iverilog -o pipetangled pipetangled.v
	vvp pipetangled

dump: dump.txt
	gtkwave dump.txt

assembly: tangled.aik testAssembly #branchTest memoryTest
	./aik tangled.aik testAssembly

clean:
	rm *.text *.data tangled
