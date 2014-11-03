// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;

// portz libraries
import Directory::*;
import CtrlMux::*;
import Portal::*;
import Leds::*;
import PortalMemory::*;
import MemTypes::*;
import MemServer::*;
import MMU::*;

import HostInterface::*;

// generated by tool
import FlashRequestWrapper::*;
import FlashIndicationProxy::*;

import StorageBridgeRequestWrapper::*;
import StorageBridgeIndicationProxy::*;

// generated by tool: hopefully only this part will change
import DmaDebugRequestWrapper::*;
import MMUConfigRequestWrapper::*;
import DmaDebugIndicationProxy::*;
import MMUConfigIndicationProxy::*;

`ifndef BSIM
import XilinxVC707DDR3::*;
import Xilinx       :: *;
import XilinxCells ::*;
import DefaultValue    :: *;
`endif
import Clocks :: *;
import DRAMImporter::*;


// defined by user
import Main::*;

import AuroraCommon::*;

typedef enum {FlashIndication, FlashRequest, HostDmaDebugIndication, HostDmaDebugRequest, HostMMUConfigRequest, HostMMUConfigIndication,
	StorageBridgeRequest, StorageBridgeIndication
	} IfcNames deriving (Eq,Bits);

interface Top_Pins;
	interface Aurora_Pins#(4) aurora_fmc1;
	interface Aurora_Clock_Pins aurora_clk_fmc1;
	
	interface Vector#(AuroraExtCount, Aurora_Pins#(1)) aurora_ext;
	interface Aurora_Clock_Pins aurora_quad119;
	interface Aurora_Clock_Pins aurora_quad117;
`ifndef BSIM
	interface DDR3_Pins_VC707 pins_ddr3;
`endif
endinterface

typedef 128 WordSz;

//module mkPortalTop(StdPortalDmaTop#(PhysAddrWidth));
module mkPortalTop#(HostType host) (PortalTop#(PhysAddrWidth,WordSz,Top_Pins,1));

	Clock clk250 = host.doubleClock;
	Reset rst250 = host.doubleReset;
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

`ifdef BSIM
	Clock ddr_buf = host.doubleClock;
	Reset ddr3ref_rst_n = host.doubleReset;
`else 
/*
	Clock clk200 = host.tsys_clk_200mhz_buf;
	Clock ddr_buf = clk200;
	Reset ddr3ref_rst_n <- mkAsyncReset( 1, curRst, ddr_buf );
	*/

	Clock clk200 = host.tsys_clk_200mhz_buf;
	Reset rst200 <- mkAsyncReset( 1, curRst, clk200 );
   /////////////////////////////////////////////////////
   ClockGenerator7Params clk_params = defaultValue();
   clk_params.clkin1_period     = 5.000;       // 200 MHz reference
   clk_params.clkin_buffer      = False;       // necessary buffer is instanced above
   clk_params.reset_stages      = 0;           // no sync on reset so input clock has pll as only load
   clk_params.clkfbout_mult_f   = 5.000;       // 1000 MHz VCO
   clk_params.clkout0_divide_f  = 10;          // unused clock 
   //clk_params.clkout0_divide_f  = 8;//10;          // unused clock 
   clk_params.clkout1_divide    = 5;           // ddr3 reference clock (200 MHz)

   ClockGenerator7 clk_gen <- mkClockGenerator7(clk_params, clocked_by clk200, reset_by rst200);
   Clock ddr_clk = clk_gen.clkout0;
   Reset rst_n <- mkAsyncReset( 1, rst200, ddr_clk );
   Reset ddr3ref_rst_n <- mkAsyncReset( 1, rst_n, clk_gen.clkout1 );
   Clock ddr_buf = clk_gen.clkout1;
   /////////////////////////////////////////////////////
`endif
	
	DRAM_Import dramImport <- mkDRAMImport(ddr_buf, ddr3ref_rst_n);
	DRAM_User dram_user = dramImport.user;
   
	/////////////////////////////////////////

   FlashIndicationProxy flashIndicationProxy <- mkFlashIndicationProxy(FlashIndication);
   StorageBridgeIndicationProxy storageBridgeIndicationProxy <- mkStorageBridgeIndicationProxy(StorageBridgeIndication);

   MainIfc hwmain <- mkMain(flashIndicationProxy.ifc, storageBridgeIndicationProxy.ifc, dram_user, clk250, rst250);
   FlashRequestWrapper flashRequestWrapper <- mkFlashRequestWrapper(FlashRequest,hwmain.request);

   StorageBridgeRequestWrapper storageBridgeRequestWrapper <- mkStorageBridgeRequestWrapper(StorageBridgeRequest, hwmain.bridgeRequest);

   //Vector#(1,  ObjectReadClient#(WordSz))   readClients = cons(hwmain.dmaReadClient, nil);
   //Vector#(1, ObjectWriteClient#(WordSz))  writeClients = cons(hwmain.dmaWriteClient, nil);
   
   let readClients = hwmain.dmaReadClient;
   let writeClients = hwmain.dmaWriteClient;

   
   MMUConfigIndicationProxy hostMMUConfigIndicationProxy <- mkMMUConfigIndicationProxy(HostMMUConfigIndication);
   MMU#(PhysAddrWidth) hostMMU <- mkMMU(0, True, hostMMUConfigIndicationProxy.ifc);
   MMUConfigRequestWrapper hostMMUConfigRequestWrapper <- mkMMUConfigRequestWrapper(HostMMUConfigRequest, hostMMU.request);

   DmaDebugIndicationProxy hostDmaDebugIndicationProxy <- mkDmaDebugIndicationProxy(HostDmaDebugIndication);
   MemServer#(PhysAddrWidth,WordSz,1) dma <- mkMemServerRW(hostDmaDebugIndicationProxy.ifc, readClients, writeClients, cons(hostMMU,nil));
   DmaDebugRequestWrapper hostDmaDebugRequestWrapper <- mkDmaDebugRequestWrapper(HostDmaDebugRequest, dma.request);

   Vector#(8,StdPortal) portals;
   portals[0] = flashRequestWrapper.portalIfc;
   portals[1] = flashIndicationProxy.portalIfc; 
   portals[2] = hostDmaDebugRequestWrapper.portalIfc;
   portals[3] = hostDmaDebugIndicationProxy.portalIfc; 
   portals[4] = hostMMUConfigRequestWrapper.portalIfc;
   portals[5] = hostMMUConfigIndicationProxy.portalIfc;
   portals[6] = storageBridgeRequestWrapper.portalIfc;
   portals[7] = storageBridgeIndicationProxy.portalIfc;
   
   StdDirectory dir <- mkStdDirectory(portals);
   let ctrl_mux <- mkSlaveMux(dir,portals);
   
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = dma.masters;
   interface leds = default_leds;

	interface Top_Pins pins;
		interface Aurora_Pins aurora_fmc1 = hwmain.aurora_fmc1;
		interface Aurora_Clock_Pins aurora_clk_fmc1 = hwmain.aurora_clk_fmc1;
	
		interface Aurora_Pins aurora_ext = hwmain.aurora_ext;
		interface Aurora_Clock_Pins aurora_quad119 = hwmain.aurora_quad119;
		interface Aurora_Clock_Pins aurora_quad117 = hwmain.aurora_quad117;
		`ifndef BSIM
		interface DDR3_Pins_VC707 pins_ddr3 = dramImport.ddr3;//.ddr3_ctrl.ddr3;
		`endif
	endinterface
endmodule


