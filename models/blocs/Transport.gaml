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
	list<string> production_outputs_T <- ["minibus", "tgv", "ter", "truck", "taxi"];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	list<string> production_trips <- ["trip_minibus", "trip_ter", "trip_tgv", "trip_taxi", "trip_truck"];
	
	map<string, float> short_or_long <- ["short"::0.95, "long"::0.05];
	
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
	
	list<string> short_transport <- ["trip_minibus","trip_bike","trip_walking"];
	list<string> long_transport <- ["trip_tgv", "trip_ter", "trip_taxi"];
	list<string> transport_name <- ["trip_minibus","trip_tgv","trip_ter","trip_taxi"];
	
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
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	production_agent get_producer{
		write "producer inside target bloc : " + producer;
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
	    			tick_trip_energy[mode] <- long_energy[mode];
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
	    			tick_trip_energy[mode] <- short_energy[mode];
	    		}
	    	}
	    	ask transport_producer {
	    		do reset_tick_counters;
	    	}
	    }
	}
	
	action population_activity(list<human> pop) {
	    // calculate trip numbers based on population
	    int agreg_pop <- 66352; // TODO : multiplier par le facteur d'agregation décidé de la population
	    int nb_population <- length(pop) * agreg_pop; 
	    //number of long trips or short trips in a month is decided by the hypothesises explained in the paper
	    int short_trips_per_week <- 14; // average of 2 trips per day
	    int long_trips_per_week <- 1;
	    
	    float nb_weeks_per_month <- 4.34524;
	    
	    int long_trips <- int(nb_population * (nb_weeks_per_month * long_trips_per_week));
	    int short_trips <- int(nb_population * (nb_weeks_per_month * short_trips_per_week));
	    
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
	        ask myself.consumer {
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
		map<string, bloc> external_producers <- []; // external producers that provide the needed resources
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
			bool ok <- true;
			loop c over: demand.keys{
				if (production_trips contains c) { // demande d'energie pour des trajets
		            loop u over: production_inputs_T {
		            	float quantity_needed <- 0.0;
		            	if (c in production_trips){
	            			quantity_needed <- tick_trip_energy[c];
	            		}
						tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
						if(external_producers.keys contains u){
							bool av <- external_producers[u].producer.produce([u::quantity_needed]);
							if not av{
								ok <- false;
							}
						}
					}
				}
				else if (production_outputs_inputs_T.keys contains c) { // demande de ressources pour de la fabrication
		            loop u over: production_inputs_T {
		            	float quantity_needed <- 0.0;
	            		// TODO: implémenter la logique de besoin de fabrication
	            		if (production_outputs_inputs_T[c].keys contains u) {
								quantity_needed <- production_outputs_inputs_T[c][u] * demand[c];
						}
						tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
						if(external_producers.keys contains u){
							bool av <- external_producers[u].producer.produce([u::quantity_needed]);
							if not av{
								ok <- false;
							}
						}
					}
					loop e over: production_emissions_T{
						if (production_output_emissions_T[c].keys contains e) {
							float quantity_emitted <- production_output_emissions_T[c][e] * demand[c];
							tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
						}
					}
					tick_production[c] <- tick_production[c] + demand[c];
				}
			}
		    return ok;
		}
		action set_supplier(string product, bloc bloc_agent){
			write name +": external producer " + bloc_agent + " set for " + product;
			external_producers[product] <- bloc_agent;
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
			consumed["trip_tgv"] <- 0.0;
			consumed["trip_ter"] <- 0.0;
			consumed["trip_taxi"] <- 0.0;
			consumed["trip_minibus"] <- 0.0;
			consumed["trip_truck"] <- 0.0;
		}
		action reset_tick_counters{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		action consume(human h) {
		    ask transport(host).long {
				map<string, float> trips <- get_tick_trips();
		        if (trips contains_key "trip_tgv") {
		        	myself.consumed["trip_tgv"] <- myself.consumed["trip_tgv"] + trips["trip_tgv"];
				}
		        if (trips contains_key "trip_ter") {
		        	myself.consumed["trip_ter"] <- myself.consumed["trip_ter"] + trips["trip_ter"];
				}
				if (trips contains_key "trip_taxi") {
		        	myself.consumed["trip_taxi"] <- myself.consumed["trip_taxi"] + trips["trip_taxi"];
				}
			}
		    ask transport(host).short {
				map<string, float> trips <- get_tick_trips();
				if (trips contains_key "trip_minibus") {
					myself.consumed["trip_minibus"] <- myself.consumed["trip_minibus"] + trips["trip_minibus"];
				}
			}
		}
	}
	
	species long_trip{
		map<string, float> long_trip_decisions_france_data <- ["trip_tgv"::0.01845,"trip_ter"::0.13205,"trip_taxi"::0.8495];
		map<string, float> long_trip_decisions_ecotopia <- ["trip_tgv"::0.60,"trip_ter"::0.40,"trip_taxi"::0.10];
		float avg_long_trip_distance <- 500.0#km; // km - average distance for long trips
		taxis my_taxis <- nil;
		ters my_ters <- nil;
		tgvs my_tgvs <- nil;
		
		// tick statistics
		map<string, float> tick_trips_by_mode <- ["trip_tgv"::0.0, "trip_ter"::0.0, "trip_taxi"::0.0];
		map<string, float> tick_energy_consumption <- ["trip_tgv"::0.0, "trip_ter"::0.0, "trip_taxi"::0.0];
		
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
			loop mode over: long_trip_decisions_ecotopia.keys {
				float mode_trips <- trip_number * long_trip_decisions_ecotopia[mode];
				tick_trips_by_mode[mode] <- tick_trips_by_mode[mode] + mode_trips;
			}
			// process energy consumption for each mode
			ask my_tgvs {
				float nb_trips <- myself.tick_trips_by_mode["trip_tgv"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_tgv <- nb_trips/passengers_per_trip;
				
				float total_km <- nb_trips_tgv * myself.avg_long_trip_distance;
				float energy_consumed <- total_km * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["trip_tgv"] <- myself.tick_energy_consumption["trip_tgv"] + energy_consumed;
			}
			ask my_ters {
				float nb_trips <- myself.tick_trips_by_mode["trip_ter"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_ter <- nb_trips/passengers_per_trip;
				
				float total_km <- nb_trips_ter * myself.avg_long_trip_distance;
				float energy_consumed <- total_km * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["trip_ter"] <- myself.tick_energy_consumption["trip_ter"] + energy_consumed;
			}
			ask my_taxis {
				float nb_trips <- myself.tick_trips_by_mode["trip_taxi"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_taxi <- nb_trips/passengers_per_trip;
				
				float total_km <- nb_trips_taxi * myself.avg_long_trip_distance;
				float energy_consumed <- total_km * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["trip_taxi"] <- myself.tick_energy_consumption["trip_taxi"] + energy_consumed;
			}
		}
		action reset_tick_counters {
			loop mode over: long_trip_decisions_ecotopia.keys {
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
		map<string, float> short_trip_decisions <- ["trip_minibus"::0.243,"trip_bike"::0.074,"trip_walking"::0.683];
		float avg_short_trip_distance <- 5.0#km; // km - average distance for short trips
		minibuses my_minibuses <- nil;
		bikes my_bikes <- nil;
		legs my_legs <- nil;
		
		// tick statistics
		map<string, float> tick_trips_by_mode <- ["trip_minibus"::0.0, "trip_bike"::0.0, "trip_walking"::0.0];
		map<string, float> tick_energy_consumption <- ["trip_minibus"::0.0, "trip_bike"::0.0, "trip_walking"::0.0];

		init {
			create minibuses number:1;
			my_minibuses <- first(minibuses);
			create bikes number:1;
			my_bikes <- first(bikes);
			create legs number:1;
			my_legs <- first(legs);
		}
		action process_short_trips(int trip_number){
			// distribute trips according to probabilities
			loop mode over: short_trip_decisions.keys {
				float mode_trips <- trip_number * short_trip_decisions[mode];
				tick_trips_by_mode[mode] <- tick_trips_by_mode[mode] + mode_trips;
			}
			// process energy consumption for each mode
			ask my_minibuses {
				float nb_trips <- myself.tick_trips_by_mode["trip_minibus"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_minibus <- nb_trips/passengers_per_trip;
				
				float total_km <- nb_trips_minibus * myself.avg_short_trip_distance;
				float energy_consumed <- (total_km / passengers_per_trip) * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["trip_minibus"] <- myself.tick_energy_consumption["trip_minibus"] + energy_consumed;
			}
			ask my_bikes {
				// bikes have no energy consumption
				myself.tick_energy_consumption["trip_bike"] <- 0.0;
			}
			ask my_bikes {
				// walking has no energy consumption
				myself.tick_energy_consumption["trip_walking"] <- 0.0;
			}
			
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
species legs parent:transport_mode {
	init{
		type <- "legs";
		number_available <- nil;
		create legs_vehicle number:1;
		ref_vehicle <- first(legs_vehicle);
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
			
			chart "Energy consumption by mode" type: series size: {0.5,0.5} position: {0, 0.5} {
			    loop mode over: transport_name {
	    			data mode value: tick_trip_energy[mode];
	    		}
			    data "total" value: tick_resources_used_T["kWh energy"];
			}
			chart "Number of long trips by mode" type: series size: {0.5,0.5} position: {0, 0} {
	    		loop mode over: long_transport {
	    			data mode value: tick_long_trips[mode];
	    		}
	    	}
	    	chart "Number of short trips by mode" type: series size: {0.5,0.5} position: {0.5, 0} {
	    		loop mode over: short_transport {
	    			data mode value: tick_short_trips[mode];
	    		}
	    	}
	    	chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_T{
			    	data e value: tick_emissions_T[e];
			    }
			}
//	    	chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
//			    loop c over: production_outputs_T{
//			    	data c value: tick_pop_consumption_T[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
//			    }
//			}
//			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
//			    loop c over: production_outputs_T{
//			    	data c value: tick_production_T[c];
//			    }
//			}
	    }
	}
}
