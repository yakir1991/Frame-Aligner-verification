//==============================================================================
// fa_pkg -- all class-based verification components of the frame aligner TB
//------------------------------------------------------------------------------
//  Compile order inside the package matters (a class must be declared before
//  it is used; the legacy build.list compiled scoreboard.sv before the model
//  it instantiates).  Forward typedefs break the generator <-> sequence
//  library cycle.
//==============================================================================
package fa_pkg;

  `include "fa_types.svh"          // constants, bug ids, logging, SVA registry
  `include "fa_ref_model.sv"       // specification reference model (+ bug knobs)
  `include "transaction.sv"        // stimulus item (spec "frame_item")
  `include "fa_checkpoint.sv"      // monitor item + test-plan checkpoints
  `include "fa_coverage.sv"        // functional coverage

  typedef class fa_sequence_lib;
  `include "generator.sv"          // stimulus stream + test selection
  `include "sequence_lib.sv"       // directed scenarios (the test plan)
  `include "driver.sv"
  `include "monitor_in.sv"
  `include "monitor_out.sv"
  `include "scoreboard.sv"
  `include "environment.sv"

endpackage
