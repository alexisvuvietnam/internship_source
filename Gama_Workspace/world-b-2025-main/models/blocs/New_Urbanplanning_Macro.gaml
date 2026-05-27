/**
* Name: Urbanplanning
* Based on the internal empty template. 
* Author: vuhoangnguyen
* Tags: 
*/
model Urbanplanning

import "../API/API.gaml"

global {
	
	list<string> production_outputs_U <- ["wooden house", "modular_house", "extended plastic modulars", "leisure place", "workplace", "school"];
	list<string> production_inputs_U <- ["m3_wood", "L water", "kg_meat", "kg_vegetables", "kg_cotton", "m² land", "kWh energy"];
	list<string> intermediate_inputs_U <- ["kg_plstic"];
	list<string> production_emissions_U <- ["gCO2e emissions"];
	
	map<string, map<string, float>> production_output_inputs_U <- [];
	map<string, map<string, float>> production_output_emissions_U <- [];
	
	map<string, float> individual_consumption_U <- ["L water" :: 0.0, "kg_meat" :: 0.0, "kg_vegetables" :: 0.0];
	
	map<string, float> tick_production_U <- [];
	map<string, float> tick_pop_consumption_U <- [];
	map<string, float> tick_resources_used_U <- [];
	map<string, float> tick_emissions_U <- [];
	
	int wooden_house_resident <- 0;
	int modular_house_resident <- 0;

	init {
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
		}
	}

}
/**
 * We define here the agricultural bloc as a species.
 * We implement the methods of the API.
 */
species urbanplanning parent:bloc{
	string name <- "urbanplanning";
	
	urban_producer producer <- nil;
	urban_consumer consumer <- nil;
	
	action setup{
		list<urban_producer> producers <- [];
		list<urban_consumer> consumers <- [];
		create urban_producer number:1 returns: producers; // instanciate the agricultural production handler
		create urban_consumer number:1 returns: consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	action tick(list<human> pop) {
		do collect_last_tick_data();
		do population_activity(pop);
	}

	
	production_agent get_producer{
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_U;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_U;
	}
	
	list<string> get_emissions_labels{
		return production_emissions_U;
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_U <- consumer.get_tick_consumption(); // collect consumption behaviors
	    	tick_resources_used_U <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_U <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_U <- producer.get_tick_emissions(); // collect emissions
	    	
	    	ask urban_consumer{ // prepare new tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask urban_producer{ // prepare new tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.urban_consumer{
    			do consume(myself); // individuals consume agricultural goods
    		}
    	}
    	 
    	ask urban_consumer{ // produce the required quantities
    		ask urban_producer{
    			loop c over: myself.consumed.keys{
		    		bool ok <- produce(self.name, [c::myself.consumed[c]]); // send the demands to the producer
		    		// note : in this example, we do not take into account the 'ok' signal.
		    	}
		    }
    	}
    }
	
	
	/**
	 * We define here the production agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is very simple here : for each behavior, we apply an average resource consumption and emissions.
	 * Some of those resources can be provided by other blocs (external producers).
	 */
	species urban_producer parent:production_agent{
		map<string, bloc> external_producers; // external producers that provide the needed resources
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		init{
			external_producers <- []; // external producers that provide the needed resources
		}
		
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for "+product;
			external_producers[product] <- bloc_agent;
		}
	
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_U{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_U{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_U{
				tick_emissions[e] <- 0.0;
			}
		}
		
		bool produce(string buyer, map<string,float> demand){
			bool ok <- true;
			loop c over: demand.keys{
				loop u over: production_inputs_U{
					float quantity_needed <- production_output_inputs_U[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand
					tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
					if(external_producers.keys contains u){ // if there is a known external producer for this product/good
						bool av <- external_producers[u].producer.produce(self.name, [u::quantity_needed]); // ask the external producer to product the required quantity
						if not av{
							ok <- false;
						}
					}
				}
				loop e over: production_emissions_U{ // apply emissions
					float quantity_emitted <- production_output_emissions_U[c][e] * demand[c];
					tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
				}
				tick_production[c] <- tick_production[c] + demand[c];
			}
			return ok;
		}
	}
	
	/**
	 * We define here the consumption agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is very simple here : each behavior as a certain probability to be selected.
	 */
	species urban_consumer parent:consumption_agent{
	
		map<string,int> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_U{
				consumed[c] <- 0;
			}
		}
		
		action reset_tick_counters{ 
    		loop c over: consumed.keys{ // reset choices counters
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){ 
		    loop c over: individual_consumption_U.keys{
		    	consumed[c] <- consumed[c]+individual_consumption_U[c];
		    }
		}
	}
}

/**
 * We define here the experiment and the displays related to urbanplanning. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_urban type: gui {
	
}