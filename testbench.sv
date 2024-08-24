// Verification Environment

`include "uvm_macros.svh"    //give access to all the macros
import uvm_pkg::*;           //give access to base class

//declaring input and output ports here this travel throughtout the testbench

class transaction extends uvm_sequence_item;
  `uvm_object_utils(transaction)
  
  rand bit [3:0] a;
  rand bit [3:0] b;
  bit [7:0] y;
  
  function new(input string path = "transaction");
    super.new(path);
  endfunction
  
endclass

//randomize the sequence and send sequence to driver through sequencer

class genarator extends uvm_sequence#(transaction);
  `uvm_object_utils(genarator)
  
  transaction tr;
  
  function new(input string path = "generator");
    super.new(path);
  endfunction
  
  virtual task body();
    repeat(15)
      begin
        tr = transaction::type_id::create("tr");
        start_item(tr);
        assert(tr.randomize());
        `uvm_info("genarator",$sformatf("a :%0d, b:%0d, y:%0d",tr.a,tr.b,tr.y), UVM_NONE);
        finish_item(tr);
      end
  endtask
  
endclass

//which receives sequence sent by sequence class through sequencer

class driver extends uvm_driver#(transaction);
  `uvm_component_utils(driver)
  
  function new(input string path="driver", uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  transaction tr;
  virtual mul_if mif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual mul_if)::get(this,"","mif",mif))
      `uvm_error("driver","unable to access the interface");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    tr = transaction::type_id::create("tr");
    forever begin
      seq_item_port.get_next_item(tr);
      mif.a <= tr.a;
      mif.b <= tr.b;
      `uvm_info("driver",$sformatf("a:%0d, b:%0d, y:%0d", tr.a,tr.b,tr.y), UVM_NONE);
      seq_item_port.item_done();
      #10;
      end
  endtask
  
endclass

//It collects the response of dut and send it to scoreboard for comparision

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  
  function new(input string path="monitor", uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  transaction tr;
  uvm_analysis_port#(transaction) send;
  virtual mul_if mif;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tr = transaction::type_id::create("tr");
    send = new("send",this);
    if(!uvm_config_db#(virtual mul_if)::get(this,"","mif",mif))
      `uvm_error("monitor","unable to access the interface");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    forever begin
      #10;
      tr.a = mif.a;
      tr.b = mif.b;
      tr.y = mif.y;
      `uvm_info("monitor",$sformatf("a:%0d, b:%0d, y:%0d",tr.a,tr.b,tr.y),UVM_NONE);
      send.write(tr);    //sending trasactoion to scoreboard
    end
  endtask
  
endclass

//receiving the response from a monitor and compare it with expected data

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  
  function new(input string path = "scoreboard", uvm_component parent = null);
    super.new(path,parent);
  endfunction
  
  uvm_analysis_imp#(transaction,scoreboard) recv;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    recv = new("recv",this);
  endfunction
  
  virtual function void write(transaction tr);
    if(tr.y == (tr.a * tr.b))
      begin
        `uvm_info("scoreboard",$sformatf(" Test Passed -> a:%0d, b:%0d, y:%0d", tr.a,tr.b,tr.y),UVM_NONE);
      end
    else
      begin
        `uvm_error("scorebord",$sformatf(" Test Failed -> a:%0d, b:%0d, y:%0d", tr.a,tr.b,tr.y));
      end
    
    $display("--------------------------------------------------------");
  endfunction
  
endclass

//It encapsulates sequencer, driver, monitor and performs connection between sequencer and driver

class agent extends uvm_agent;
  `uvm_component_utils(agent)
  
  function new(input string path = "agent", uvm_component parent = null);
    super.new(path,parent);
  endfunction
  
  uvm_sequencer#(transaction) seqr;
  driver drv;
  monitor mon;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seqr = uvm_sequencer#(transaction)::type_id::create("seqr",this);
    drv = driver::type_id::create("drv",this);
    mon = monitor::type_id::create("mon",this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
  
endclass

//It encapsulates agent and scoreboard and performs connection between monitor in agent and scoreboard.

class env extends uvm_env;
  `uvm_component_utils(env)
  
  function new(input string path = "env",uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  agent a;
  scoreboard sco;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    a = agent::type_id::create("a",this);
    sco = scoreboard::type_id::create("sco",this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a.mon.send.connect(sco.recv);
  endfunction
  
endclass

//It will encapsulates an environment and it strats the sequence and holds the simulation till the completion sending and reciving all the sequences

class test extends uvm_test;
  `uvm_component_utils(test)
  
  function new(input string path="test", uvm_component parent=null);
    super.new(path,parent);
  endfunction
  
  env e;
  genarator gen;
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    e = env::type_id::create("e",this);
    gen = genarator::type_id::create("gen");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    gen.start(e.a.seqr);
    #10;  //this is to makesure that to process the last stimuli that we sent from sequence
    phase.drop_objection(this);
  endtask
  
endclass

//Testbench top

module tb;
  mul_if mif();
  
  mul dut(.a(mif.a),.b(mif.b),.y(mif.y));
  
  initial begin
    uvm_config_db#(virtual mul_if)::set(null,"*","mif",mif);
    run_test("test");
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule
    
