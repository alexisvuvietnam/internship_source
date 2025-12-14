/**
* Name: Transport
* Based on the internal empty template. 
* Author: williamsardon
* Tags: 
*/

model Transport
import "../API/API.gaml"

global {
	/* Setup */
	list<string> production_inputs_T <- ["kWh energy"];
	list<string> production_outputs_T <- ["minibus", "train", "truck", "taxi"];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	
	/* Production data */
	map<string, map<string, float>> production_outputs_inputs_T <-
	["minibus" :: ["kWh energy" :: 51240.0, "kg plastic" :: 2390.0],  
	"tgv" :: ["kWh energy" :: 1001250.0, "kg plastic" :: 46700.0],
	"ter" :: ["kWh energy" :: 616185.0, "kg plastic" :: 28740.0],
	"velo" :: ["kWh energy" :: 38.0, "kg plastic" :: 1.8],
	"taxi" :: ["kWh energy" :: 34700.0, "kg plastic" :: 180.0]];
	map<string, map<string, float>> production_output_emissions_T <- 
	["minibus" :: ["gCO2e emissions" :: 9560000.0],
	"tgv" :: ["gCO2e emissions" :: 326900000.0],
	"ter" :: ["gCO2e emissions" :: 201180000.0],
	"velo" :: ["gCO2e emissions" :: 150000.0],
	"taxi" :: ["gCO2e emissions" :: 10000000.0]];
	
	/* Counters & Stats */
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];
	
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
species transport parent:bloc{
	string name <- "transport";
	transport_producer producer <- nil;
	transport_consumer consumer <- nil;
	
	action setup{
		list<transport_producer> producers <- [];
		list<transport_consumer> consumers <- [];
		create transport_producer number:1 returns:producers;
		create transport_consumer number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop); // a remplacer
	}
	
	production_agent get_producer{
		write "producer inside target bloc : "+producer;
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_T;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_T;
	}
	
	action set_external_producer(string product, bloc bloc_agent){
		// do nothing
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_T <- consumer.get_tick_consumption(); // collect consumption behaviors
    		tick_resources_used_T <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_T <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_T <- producer.get_tick_emissions(); // collect emissions
    	
	    	ask transport_consumer{ // prepare next tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask transport_producer{ // prepare next tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{
    		ask myself.transport_consumer{
    			do consume(myself);
    		}
    	}
    	 
    	ask transport_consumer{ // produce the required quantities
    		ask transport_producer{
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]);
		    	}
		    } 
    	}
    }

	species transport_producer parent:production_agent{
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
			loop u over: production_inputs_T{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_T{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_T{
				tick_emissions[e] <- 0.0;
			}
		}
		
		bool produce(map<string,float> demand){
			// TODO : la production concernera ici la création de nouvau véhicule
			return true; // always return 'ok' signal
		}
		
		action set_supplier(string product, bloc bloc_agent){
			// do nothing
		}
	}
	
	species transport_consumer parent:consumption_agent{
		map<string, float> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		init{
			loop c over: production_outputs_T{
				consumed[c] <- 0;
			}
		}
		action reset_tick_counters{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		action consume(human h){
		    string choice <- one_of(production_outputs_T);
		}
	}
}

/* Global species for agregating stats */
/*
 * VEHICLE REFERENCES FOR CALCULATIONS
 */
species vehicle {
	string name;
	float consumption_per_km; // kWh/km
	float avg_speed; //km_per_hour
	int max_passenger_capacity <- 0;
	float max_delivery_capacity <- 0.0;
	float fabrication_cost;
}
species taxi_vehicle parent:vehicle {
	init {
		name <- "taxi_vehicle";
		consumption_per_km <- 0.17;
		avg_speed <- 100.0;
		max_passenger_capacity <- 4;
	}
}
species tgv_vehicle parent:vehicle {
	init {
		name <- "tgv_vehicle";
		consumption_per_km <- 13.0;
		avg_speed <- 300.0;
		max_passenger_capacity <- 550;
	}
}
species ter_vehicle parent:vehicle {
	init {
		name <- "ter_vehicle";
		consumption_per_km <- 14.2;
		avg_speed <- 100.0;
		max_passenger_capacity <- 250;
	}
}
species minibus_vehicle parent:vehicle {
	init {
		name <- "minibus_vehicle";
		consumption_per_km <- 2.0;
		avg_speed <- 25.0;
		max_passenger_capacity <- 90;
	}
}
species bike_vehicle parent:vehicle {
	init {
		name <- "bike_vehicle";
		consumption_per_km <- 0.0;
		avg_speed <- 15.0;
		max_passenger_capacity <- 1;
	}
}
species truck_vehicle parent:vehicle {
	init {
		name <- "truck_vehicle";
		consumption_per_km <- 2.0;
		avg_speed <- 67.0;
		max_delivery_capacity <- 0.0; // TODO remplacer avec les vraies données
	}
}

/* Species of transportation modes, used to update the number of available vehicles
 * and to agregate stats
 */
species transport_mode {
	string type; // truck, taxi, train ...
	int number_available;
	vehicle ref_vehicle;
	
	action update_number_available(int new_number){
		number_available <- new_number;
	}
}
species taxis parent:transport_mode {
	init{
		type <- "taxis";
		number_available <- 119000;
		create taxi_vehicle;
	}
}
species tgv parent:transport_mode {
	init{
		type <- "tgv";
		number_available <- 350;
		create tgv_vehicle;
	}
}
species ter parent:transport_mode {
	init{
		type <- "ter";
		number_available <- 2500;
		create ter_vehicle;
	}
}
species minibuses parent:transport_mode {
	init{
		type <- "minibuses";
		number_available <- 28000;
		create minibus_vehicle;
	}
}
species bikes parent:transport_mode {
	init{
		type <- "bikes";
		number_available <- 16600000;
		create bike_vehicle;
	}
}
species trucks parent:transport_mode {
	init{
		type <- "trucks";
		number_available <- 305800;
		create truck_vehicle;
	}
}

/**
 * We define here the experiment and the displays related to transport. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_transport type: gui {
	output {
		display Transport_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_T{
			    	data c value: tick_pop_consumption_T[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_T{
			    	data c value: tick_production_T[c];
			    }
			}
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5} {
			    loop r over: production_inputs_T{
			    	data r value: tick_resources_used_T[r];
			    }
			}
			chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_T{
			    	data e value: tick_emissions_T[e];
			    }
			}
	    }
	}
}