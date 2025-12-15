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
	
	map<string, float> short_or_long <- ["short"::0.8, "long"::0.2];
	
	/* Production data */
	map<string, map<string, float>> production_outputs_inputs_T <-
	["minibus" :: ["kWh energy" :: 51240.0, "kg plastic" :: 2390.0],  
	"tgv" :: ["kWh energy" :: 1001250.0, "kg plastic" :: 46700.0],
	"ter" :: ["kWh energy" :: 616185.0, "kg plastic" :: 28740.0],
	"bike" :: ["kWh energy" :: 38.0, "kg plastic" :: 1.8],
	"taxi" :: ["kWh energy" :: 34700.0, "kg plastic" :: 180.0]];
	map<string, map<string, float>> production_output_emissions_T <- 
	["minibus" :: ["gCO2e emissions" :: 9560000.0],
	"tgv" :: ["gCO2e emissions" :: 326900000.0],
	"ter" :: ["gCO2e emissions" :: 201180000.0],
	"bike" :: ["gCO2e emissions" :: 150000.0],
	"taxi" :: ["gCO2e emissions" :: 10000000.0]];
	
	/* Counters & Stats */
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];
	
	list<string> short_transport <- ["minibus","bike","walking"];
	list<string> long_transport <- ["tgv", "ter", "taxi"];
	list<string> transport_name <- ["minibus","tgv","ter","taxi"];
	
	// trip statistics
	map<string, float> tick_long_trips <- [];
	map<string, float> tick_short_trips <- [];
	map<string, float> tick_trip_energy <- [];
	
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
	
	long_trip long <- nil;
	short_trip short <- nil;
	
	action setup{
		list<transport_producer> producers <- [];
		list<transport_consumer> consumers <- [];
		create transport_producer number:1 returns:producers;
		create transport_consumer number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);
		
		create long_trip number:1;
		create short_trip number:1;
		long <- first(long_trip);
		short <- first(short_trip);
	}
	
	action tick(list<human> pop){
		int total_trips <- 10000;
		do collect_last_tick_data();
		do population_activity(pop, total_trips);
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
	    	
	    	// collect trip statistics
	    	ask long {
	    		tick_long_trips <- get_tick_trips();
	    		map<string, float> long_energy <- get_tick_energy();
	    		// aggregate into global statistics
	    		loop mode over: long_energy.keys {
	    			if (tick_trip_energy[mode] = nil) {
	    				tick_trip_energy[mode] <- 0.0;
	    			}
	    			tick_trip_energy[mode] <- tick_trip_energy[mode] + long_energy[mode];
	    		}
	    	}
	    	
	    	ask short {
	    		tick_short_trips <- get_tick_trips();
	    		map<string, float> short_energy <- get_tick_energy();
	    		// aggregate into global statistics
	    		loop mode over: short_energy.keys {
	    			if (tick_trip_energy[mode] = nil) {
	    				tick_trip_energy[mode] <- 0.0;
	    			}
	    			tick_trip_energy[mode] <- tick_trip_energy[mode] + short_energy[mode];
	    		}
	    	}
	    }
	}
	
	action population_activity(list<human> pop, int nb_trajets) {
	    // calculate trip numbers based on population
	    int total_trips <- length(pop);
	    int long_trips <- int(total_trips * short_or_long["long"]);
	    int short_trips <- int(total_trips * short_or_long["short"]);
	    
	    // reset and process trips
	    ask long {
	        do reset_tick_counters();
	        do process_long_trips(long_trips);
	    }
	    ask short {
	        do reset_tick_counters();
	        do process_short_trips(short_trips);
	    }
	    ask pop {
	        ask myself.transport_consumer {
	            do consume(myself);
	        }
	    }
	    
	    ask transport_consumer {
	        ask transport_producer {
	            loop c over: myself.consumed.keys {
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
			// TODO : la création de nouvau véhicule
		    // collect from long trips
		    ask transport(host).long {
		        tick_trip_energy <- get_tick_energy();
		        // sum all energy consumption
		        loop mode over: tick_trip_energy.keys {
		            myself.tick_resources_used["kWh energy"] <- 
		                myself.tick_resources_used["kWh energy"] + tick_trip_energy[mode];
		        }
		    }
		    // collect from short trips
		    ask transport(host).short {
		        tick_trip_energy <- get_tick_energy();
		        // sum all energy consumption
		        loop mode over: tick_trip_energy.keys {
		            myself.tick_resources_used["kWh energy"] <- 
		            	myself.tick_resources_used["kWh energy"] + tick_trip_energy[mode];
		        }
		    }
		    return true;
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
		action consume(human h) {
		    // collect from long_trip
		    ask transport(host).long {
		        map<string, float> trips <- get_tick_trips();
		        // combine TGV and TER into train
		        if trips contains_key "tgv" or trips contains_key "ter" {
		            float train_trips <- (trips contains_key "tgv" ? trips["tgv"] : 0.0) + 
		                                 (trips contains_key "ter" ? trips["ter"] : 0.0);
		            myself.consumed["train"] <- myself.consumed["train"] + train_trips;
		        }
		        // track taxi trips
		        if trips contains_key "taxi" {
		            myself.consumed["taxi"] <- myself.consumed["taxi"] + trips["taxi"];
		        }
		    }
		    // collect from short_trip
		    ask transport(host).short {
		        map<string, float> trips <- get_tick_trips();
		        if trips contains_key "minibus" {
		            myself.consumed["minibus"] <- myself.consumed["minibus"] + trips["minibus"];
		        }
			}
		}
	}
	
	species long_trip{
		map<string, float> long_trip_decisions <- ["tgv"::0.3,"ter"::0.5,"taxi"::0.2];
		float avg_long_trip_distance <- 500.0; // km - average distance for long trips
		
		taxis my_taxis <- nil;
		ters my_ters <- nil;
		tgvs my_tgvs <- nil;
		
		// tick statistics
		map<string, float> tick_trips_by_mode <- ["tgv"::0.0, "ter"::0.0, "taxi"::0.0];
		map<string, float> tick_energy_consumption <- ["tgv"::0.0, "ter"::0.0, "taxi"::0.0];
		map<string, float> tick_emissions <- ["tgv"::0.0, "ter"::0.0, "taxi"::0.0];
		
		init {
			create taxis number:1;
			my_taxis <- first(taxis);
			create ters number:1;
			my_ters <- first(ters);
			create tgvs number:1;
			my_tgvs <- first(tgvs);
		}
		
		action process_long_trips(int trip_number){
			// distribute trips according to probabilities
			loop mode over: long_trip_decisions.keys {
				float mode_trips <- trip_number * long_trip_decisions[mode];
				tick_trips_by_mode[mode] <- tick_trips_by_mode[mode] + mode_trips;
			}
			// calculate energy consumption for each mode
			ask my_tgvs {
				float trips <- myself.tick_trips_by_mode["tgv"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float total_km <- trips * myself.avg_long_trip_distance;
				float energy_consumed <- (total_km / passengers_per_trip) * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["tgv"] <- myself.tick_energy_consumption["tgv"] + energy_consumed;
			}
			ask my_ters {
				float trips <- myself.tick_trips_by_mode["ter"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float total_km <- trips * myself.avg_long_trip_distance;
				float energy_consumed <- (total_km / passengers_per_trip) * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["ter"] <- myself.tick_energy_consumption["ter"] + energy_consumed;
			}
			ask my_taxis {
				float trips <- myself.tick_trips_by_mode["taxi"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float total_km <- trips * myself.avg_long_trip_distance;
				float energy_consumed <- (total_km / passengers_per_trip) * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["taxi"] <- myself.tick_energy_consumption["taxi"] + energy_consumed;
			}
		}
		action reset_tick_counters {
			loop mode over: long_trip_decisions.keys {
				tick_trips_by_mode[mode] <- 0.0;
				tick_energy_consumption[mode] <- 0.0;
			}
		}
		map<string, float> get_tick_trips {
			return copy(tick_trips_by_mode);
		}
		map<string, float> get_tick_energy {
			return copy(tick_energy_consumption);
		}
	}
	
	species short_trip{
		map<string, float> short_trip_decisions <- ["minibus"::0.243,"bike"::0.074,"walking"::0.683];
		float avg_short_trip_distance <- 5.0; // km - average distance for short trips
		
		minibuses my_minibuses <- nil;
		bikes my_bikes <- nil;
		
		// tick statistics
		map<string, float> tick_trips_by_mode <- ["minibus"::0.0, "bike"::0.0, "walking"::0.0];
		map<string, float> tick_energy_consumption <- ["minibus"::0.0, "bike"::0.0, "walking"::0.0];
		map<string, float> tick_emissions <- ["minibus"::0.0, "bike"::0.0, "walking"::0.0];
		
		init {
			create minibuses number:1;
			my_minibuses <- first(minibuses);
			create bikes number:1;
			my_bikes <- first(bikes);
		}
		action process_short_trips(int trip_number){
			// distribute trips according to probabilities
			loop mode over: short_trip_decisions.keys {
				float mode_trips <- trip_number * short_trip_decisions[mode];
				tick_trips_by_mode[mode] <- tick_trips_by_mode[mode] + mode_trips;
			}
			// calculate energy consumption for each mode
			ask my_minibuses {
				float trips <- myself.tick_trips_by_mode["minibus"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float total_km <- trips * myself.avg_short_trip_distance;
				float energy_consumed <- (total_km / passengers_per_trip) * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["minibus"] <- myself.tick_energy_consumption["minibus"] + energy_consumed;
			}
			ask my_bikes {
				float trips <- myself.tick_trips_by_mode["bike"];
				// bikes have no energy consumption
				myself.tick_energy_consumption["bike"] <- 0.0;
			}
			// walking has no energy consumption
			tick_energy_consumption["walking"] <- 0.0;
		}
		
		action reset_tick_counters {
			loop mode over: short_trip_decisions.keys {
				tick_trips_by_mode[mode] <- 0.0;
				tick_energy_consumption[mode] <- 0.0;
			}
		}
		map<string, float> get_tick_trips {
			return copy(tick_trips_by_mode);
		}
		map<string, float> get_tick_energy {
			return copy(tick_energy_consumption);
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
species legs_vehicle parent:vehicle {
	init {
		name <- "legs_vehicle";
		consumption_per_km <- 0.0;
		avg_speed <- 4.0;
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

/* 
 * Species of transportation modes, used to update the number of available vehicles
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
		create taxi_vehicle number:1;
		ref_vehicle <- first(taxi_vehicle);
	}
}
species tgvs parent:transport_mode {
	init{
		type <- "tgvs";
		number_available <- 350;
		create tgv_vehicle number:1;
		ref_vehicle <- first(tgv_vehicle);
	}
}
species ters parent:transport_mode {
	init{
		type <- "ters";
		number_available <- 2500;
		create ter_vehicle;
		ref_vehicle <- first(ter_vehicle);
	}
}
species minibuses parent:transport_mode {
	init{
		type <- "minibuses";
		number_available <- 28000;
		create minibus_vehicle;
		ref_vehicle <- first(minibus_vehicle);
	}
}
species bikes parent:transport_mode {
	init{
		type <- "bikes";
		number_available <- 16600000;
		create bike_vehicle number:1;
		ref_vehicle <- first(bike_vehicle);
	}
}
species trucks parent:transport_mode {
	truck_vehicle truck <- nil;
	init{
		type <- "trucks";
		number_available <- 305800;
		create truck_vehicle number:1;
		ref_vehicle <- first(truck_vehicle);
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
		display Transport_information type: 2d{
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
experiment run_transport_trips type: gui {
	output {
		display Trip_Statistics {
	    	chart "Long trips by mode" type: series size: {0.5,0.5} position: {0, 0} {
	    		loop mode over: long_transport {
	    			data mode value: tick_long_trips[mode];
	    		}
	    	}
	    	chart "Short trips by mode" type: series size: {0.5,0.5} position: {0.5, 0} {
	    		loop mode over: short_transport {
	    			data mode value: tick_short_trips[mode];
	    		}
	    	}
	    	chart "Energy consumption by mode (kWh)" type: series size: {0.5,0.5} position: {0, 0.5} {
	    		loop mode over: transport_name {
	    			data mode value: tick_trip_energy[mode];
	    		}
	    	}
	    }
    }
}
