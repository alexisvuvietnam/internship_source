/**
* Name: Urbanplanning
* Based on the internal empty template. 
* Author: williamsardon
* Tags: 
*/


model Urbanplanning

import "../API/API.gaml"

global {
	/* Setup */
	// TODO : adapter les productions et les ressources demandées sur les vrais variables et valeurs
	list<string> production_inputs_U <- ["kg_plastic", "kg_wood"];
	list<string> production_outputs_U <- ["house"];
	list<string> production_emissions_U <- ["gCO2e emissions"];
	
	/* Production data */
	// TODO : adapter les production et le cout de celle ci sur les bonnes
	map<string, map<string, float>> production_output_inputs_U <- ["house" :: ["kg_wood" :: 0.0, "kg_plastic" :: 3000.0]];
	map<string, map<string, float>> production_output_emissions_U <- ["house" :: ["gCO2e emissions" :: 1000000.0]];
	
	map<string, float> indivudual_consumption_U <- ["house"::1.0];
	map<string, float> supplies_U <- ["house"::0.0];
	map<string, int> time_cost_U <- ["house"::3];
	
	/* Counters & Stats */
	map<string, float> tick_production_U <- [];
	map<string, float> tick_pop_consumption_U <- [];
	map<string, float> tick_resources_used_U <- [];
	map<string, float> tick_emissions_U <- [];
	list<map<string, float>> production_history_U <- [];
	
	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
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
		create urban_producer number:1 returns:producers;
		create urban_consumer number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);
		
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	production_agent get_producer{
		write "producer inside target bloc : "+producer;
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_U;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_U;
	}

	
	action set_external_producer(string product, bloc bloc_agent){
		// do nothing
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_U <- consumer.get_tick_consumption(); // collect consumption behaviors
    		tick_resources_used_U <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_U <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_U <- producer.get_tick_emissions(); // collect emissions
    	
			//loop c over: production_outputs_U{
            //    production_history_U[c] <- production_history_U[c] + [tick_production_U[c]];
            //}
    	
	    	ask urban_consumer{ // prepare next tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask urban_producer{ // prepare next tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.urban_consumer{
    			do consume(myself);
    		}
    	}
    	 
    	ask urban_consumer{ // produce the resuired quantities
    		ask urban_producer{
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]);
		    	}
		    }
    	}
    }

	/**
	 * We define here the production agent of the urbanplanning bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production will be used in the implementation of 
	 */
	species urban_producer parent:production_agent{
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		map<string, float> get_tick_emissions{
			return tick_emissions;
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
		
		bool produce(map<string,float> demand){ // apply the input
			// TODO : la production concernera ici la création de nouvau véhicule
			list<map<string, float>> valeurs <- [];
			loop c over: demand.keys{
				demand[c] <- demand[c] - supplies_U[c];
				if(demand[c] < 0){
					demand[c] <- 0;
				}
				loop u over: production_inputs_U{  // needs (resources consumed/emitted) for this demand
					float quantity_needed <- production_output_inputs_U[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand
					tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
				}
				loop e over: production_emissions_U{ // apply emissions
					float quantity_emitted <- production_output_emissions_U[c][e] * demand[c];
					tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
				}
				tick_production[c] <- tick_production[c] + demand[c];

				add [c::(demand[c] + supplies_U[c])] to: valeurs;

				if(length(production_history_U) >= time_cost_U[c]){
					float to_build <- (production_history_U at (length(production_history_U) - time_cost_U[c]))[c];
					supplies_U[c] <- to_build;
				}
				
				
			}
			//add tick_production to: production_history_U;
			production_history_U <- production_history_U + valeurs;
			
			return true; // always return 'ok' signal
		}
		
		action set_supplier(string product, bloc bloc_agent){
			// do nothing
		}
	}
	
	/**
	 * We define here the consumption agent of the urbanplanning bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is minimalistic here : we apply a random energy consumption for everyone.
	 */
	species urban_consumer parent:consumption_agent{
		map<string, float> consumed <- [];
		map<string, float> possession <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_U{
				consumed[c] <- 0;
				possession[c] <- 0;
			}
		}
		
		action reset_tick_counters{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){
		    loop c over: indivudual_consumption_U.keys{
				consumed[c] <- consumed[c]+indivudual_consumption_U[c];
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
	output {
		display Urban_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_U{
			    	data c value: tick_pop_consumption_U[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_U{
			    	data c value: tick_production_U[c];
			    }
			}
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5} {
			    loop r over: production_inputs_U{
			    	data r value: tick_resources_used_U[r];
			    }
			}
			chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_U{
			    	data e value: tick_emissions_U[e];
			    }
			}
	    }
	}
}