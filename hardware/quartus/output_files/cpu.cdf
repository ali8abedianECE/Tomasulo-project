/* Quartus Prime Version 18.1.0 Build 625 09/12/2018 SJ Lite Edition */
JedecChain;
	FileRevision(JESD32A);
	DefaultMfr(6E);

	P ActionCode(Ign)
		Device PartName(SOCVHPS) MfrSpec(OpMask(0));
	P ActionCode(Cfg)
		Device PartName(5CSEMA5F31) Path("C:/Users/a_abe/Downloads/Tomasulo-project/hardware/quartus/output_files/") File("cpu.sof") MfrSpec(OpMask(1) SEC_Device(QSPI128MB) Child_OpMask(1 0));

ChainEnd;

AlteraBegin;
	ChainType(JTAG);
AlteraEnd;
