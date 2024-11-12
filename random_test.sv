//The test program is the primary script for running a verification scenario.
// It initializes the environment, configures the generator’s workload, and executes
// the test flow. This setup enables a structured and automated approach to verifying
// the DUT, using the full suite of verification components defined in the environment.

program test(frame_inf i_inf);
  
  // Declare environment instance
  environment env;
  
  initial begin
    // Create environment
    env = new(i_inf);
    
    // Set the repeat count of generator 
    env.gen.repeat_count = 800;
    
    // Run the environment
    env.run();
  end
endprogram
