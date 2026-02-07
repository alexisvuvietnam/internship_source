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

	// TODO : ARBITRARY VALUES TO REPLACE
	float max_capacity_highway <- 200.0;
	float max_capacity_main_road <- 100.0;
	float max_capacity_local_road <- 50.0;

	// min length of a road to be determined a certain type (highway, main_road or local_road)
	float min_length_highway <- 10.0 #km;
	float min_length_main_road <- 5.0 #km;

	/* Production data */
	map<string, map<string, float>> production_outputs_inputs_T <-
	["minibus" :: ["kWh energy" :: 3520.0, "kg plastic" :: 2395.0],  
	"tgv" :: ["kWh energy" :: 68649.0, "kg plastic" :: 46700.0],
	"ter" :: ["kWh energy" :: 42248.0, "kg plastic" :: 28740.0],
	"bike" :: ["kWh energy" :: 1.5, "kg plastic" :: 1.0],
	"taxi" :: ["kWh energy" :: 265.0, "kg plastic" :: 180.0]];
	map<string, map<string, float>> production_output_emissions_T <- 
	["minibus" :: ["gCO2e emissions" :: 1856000.0],
	"tgv" :: ["gCO2e emissions" :: 36193000.0],
	"ter" :: ["gCO2e emissions" :: 22276000.0],
	"bike" :: ["gCO2e emissions" :: 775.0],
	"taxi" :: ["gCO2e emissions" :: 140000.0]];
	
	/* Counters & Stats */
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];

	// renouvelement des véhicule
	int r_m <- 1;
	map<string,int> production_vehicules <- [
	    "taxi"::1500*r_m,       // 2,000 per month (~24k/year)
	    "tgv"::25*r_m,           // ~1 per month (~12/year)
	    "ter"::650*r_m,           // ~7 per month (~84/year)
	    "minibus"::5500*r_m,      // ~5760 per month
	    "bike"::400*r_m        // 400 per month
	];
	
	
	list<string> short_transport <- ["trip_minibus","trip_bike","trip_walking"];
	list<string> long_transport <- ["trip_tgv", "trip_ter", "trip_taxi"];
	list<string> transport_name <- ["trip_minibus", "trip_tgv", "trip_ter", "trip_taxi"];
	//list<string> transport_names_list <- ["minibus","tgv","ter","taxi", "bikes"]; //to change
	map<string, string> mode_to_trip <- ["minibus"::"trip_minibus", "tgv"::"trip_tgv", "ter"::"trip_ter", "taxi"::"trip_taxi"];
	list<string> transport_modes <- keys(mode_to_trip);

	// trip statistics
	map<string, float> tick_long_trips <- [];
	map<string, float> tick_short_trips <- [];
	map<string, float> tick_trip_energy <- [];
	map<string, float> transport_usage <- []; // % de trajets utilisés par rapport au max possible
	list<string> transport_usage_keys <- ['trip_tgv', 'trip_ter', 'trip_taxi', 'trip_minibus', 'trip_bike'];
	//map<string, float> transport_usage <- ["trip_minibus"::0.0, "trip_tgv"::0.0, "trip_ter"::0.0, "trip_taxi"::0.0];
	map<string, float> km_per_tick <- ["taxi"::0.0, "tgv"::0.0, "ter"::0.0, "minibus"::0.0, "bike"::0.0];

	// max trip per month
	map<string, int> vehicle_max_trips <- ["taxi"::30, "tgv"::90, "ter"::120, "minibus"::250, "bike"::100];

	init { // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0) {
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}

	}

}

/**
 * We define here the transport bloc as a species.
 * We implement the methods of the API.
 */
species transport parent: bloc {
	string name <- "transport";
	transport_producer producer <- nil;
	transport_consumer consumer <- nil;

	// demography informations
	list<mini_city> mini_cities <- [];
	list<main_city> main_cities <- [];
	int nb_mini_cities_per_city;
	int mini_city_population;
	int city_population;
	graph transport_network;
	bool use_gis;

	// parameters of Small-World (Watts-Strogatz) for the creation of the network
	int k_neighbors;
	float rewiring_probability <- 0.0; // TODO: at 0 for now because of an error in the deletion of transport link
	long_trip long <- nil;
	short_trip short <- nil;

	//number of long trips or short trips in a month is decided by the hypothesises explained in the paper
	int short_trips_per_week <- 14; // average of 2 trips per day
	int long_trips_per_week <- 1;

	// boolean values to handle shortage
	bool do_long_trips <- true;
	bool do_short_trips <- true;
	list<transport_mode> transport_modes_available;
	taxis my_taxis <- nil;
	ters my_ters <- nil;
	tgvs my_tgvs <- nil;
	minibuses my_minibuses <- nil;
	bikes my_bikes <- nil;
	legs my_legs <- nil;

	action setup {
		create taxis number: 1;
		my_taxis <- first(taxis);
		create ters number: 1;
		my_ters <- first(ters);
		create tgvs number: 1;
		my_tgvs <- first(tgvs);
		create minibuses number: 1;
		my_minibuses <- first(minibuses);
		create bikes number: 1;
		my_bikes <- first(bikes);
		create legs number: 1;
		my_legs <- first(legs);
		list<transport_producer> producers <- [];
		list<transport_consumer> consumers <- [];
		create transport_producer number: 1 returns: producers;
		create transport_consumer number: 1 returns: consumers;
		producer <- first(producers);
		consumer <- first(consumers);

		/*
		 * Generation of the transport network
		 */
		if (use_gis) {
		// verification that mini-cities is not empty
			if empty(mini_cities) {
				write "ERREUR: mini_cities est vide dans transport.setup()";
				return;
			}

			int total_mini_cities <- length(mini_cities);
			// verification that the number of mini-cities isnt lower than 3
			if total_mini_cities < 3 {
				write "ERREUR: Pas assez de mini-villes (" + total_mini_cities + "). Minimum: 3";
				return;
			}

			nb_mini_cities_per_city <- int(city_population / mini_city_population);
			// calculate the k_neighbors opt for watts-strogatz 
			k_neighbors <- max([2, int(sqrt(total_mini_cities))]);
			// force k even (recommended for watts-strogatz)
			if mod(k_neighbors, 2) = 1 {
				k_neighbors <- k_neighbors + 1;
			}
			// verification that k<n
			k_neighbors <- min([k_neighbors, total_mini_cities - 1]);
			// write "K voisins calculé: " + k_neighbors;
			// generate small-world
			write "Génération du réseau de transport...";
			do create_network();
			write "Création de " + length(transport_link) + " liens de transport";
			// add inter city links
			do add_inter_city_links();
			// rebuild the graph
			transport_network <- as_edge_graph(list(transport_link));
		}

		write "Réseau de transport généré avec succès";
		write "Nombre d'autoroutes : " + length(list(transport_link where (each.link_type = "highway")));
		write "Nombre de routes principales : " + length(list(transport_link where (each.link_type = "main_road")));
		write "Nombre de routes locales : " + length(list(transport_link where (each.link_type = "local_road")));
		create long_trip number: 1;
		create short_trip number: 1;
		long <- first(long_trip);
		short <- first(short_trip);
	}

	action tick (list<human> pop) {
		do collect_last_tick_data();
		do population_activity(pop);
		do update_transport_available();
	}

	action create_network {
	// link the k closest cities
		loop i from: 0 to: length(mini_cities) - 1 {
			mini_city node_i <- mini_cities[i];
			// order the other cities according to their proximity to mini city i (node_i)
			list<mini_city> neighbors <- mini_cities where (each != node_i) sort_by (each.location distance_to node_i.location);
			// connect to the k firts
			loop j from: 0 to: min([k_neighbors - 1, length(neighbors) - 1]) {
				mini_city node_j <- neighbors[j];
				// verify if the link exists
				if !link_exists(node_i, node_j) {
					string type <- determine_link_type(node_i, node_j);
					// verify there are no highway already between the two constellations
					if type = "highway" {
						if highway_exists(node_i, node_j) {
							break;
						}

					}

					create transport_link {
						node_a <- node_i;
						node_b <- node_j;
						shape <- line([node_i.location, node_j.location]);
						length <- shape.perimeter / 1000;
						link_origin <- "regular";
						link_type <- myself.determine_link_type(node_i, node_j);
						max_capacity <- (link_type = "highway") ? max_capacity_highway : ((link_type = "main_road") ? max_capacity_main_road : max_capacity_local_road);
					}

				}

			}

		}
		// rewiring (create long distance shortcuts)
		list<transport_link> regular_links <- list(transport_link where (each.link_origin = "regular"));
		loop link over: regular_links {
		// rewire with a p_probability
			if flip(rewiring_probability) {
				mini_city node_a <- link.node_a;
				mini_city node_b <- link.node_b;
				// choose a new target node thats far away
				list<mini_city> far_nodes <- mini_cities where (each != node_a and each != node_b and (each.location distance_to node_a.location) > min_length_main_road);
				if !empty(far_nodes) {
					mini_city new_target <- one_of(far_nodes);
					if !link_exists(node_a, new_target) and new_target != nil and node_a != nil {
					// delete the old link
						ask link {
							do die;
						}
						// create the new rewired link
						create transport_link {
							node_a <- node_a;
							node_b <- new_target;
							shape <- line([node_a.location, new_target.location]);
							length <- shape.perimeter / 1000;
							link_origin <- "rewired";
							link_type <- myself.determine_link_type(node_a, new_target);
							max_capacity <- (link_type = "highway") ? max_capacity_highway : ((link_type = "main_road") ? max_capacity_main_road : max_capacity_local_road);
						}

					}

				}

			}

		}

	}

	production_agent get_producer {
		write "producer inside target bloc : " + producer;
		return producer;
	}

	list<string> get_output_resources_labels {
		return production_outputs_T;
	}

	list<string> get_input_resources_labels {
		return production_inputs_T;
	}

	action set_external_producer (string product, bloc bloc_agent) {
	// do nothing
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_pop_consumption_T <- consumer.get_tick_consumption(); // collect consumption behaviors
			tick_resources_used_T <- producer.get_tick_inputs_used(); // collect resources used
			tick_production_T <- producer.get_tick_outputs_produced(); // collect production
			tick_emissions_T <- producer.get_tick_emissions(); // collect emissions
			map<string, float> tick_usage_long <- [];
			map<string, float> tick_usage_short <- [];

			// collect trip statistics
			if (long != nil) {
				ask long {
					tick_long_trips <- get_tick_trips();
					tick_usage_long <- get_tick_usage();
					map<string, float> long_energy <- get_tick_energy();
					loop mode over: long_energy.keys {
						if (tick_trip_energy[mode] = nil) {
							tick_trip_energy[mode] <- 0.0;
						}

						tick_trip_energy[mode] <- long_energy[mode];
					}

				}

			}

			if (short != nil) {
				ask short {
					tick_short_trips <- get_tick_trips();
					tick_usage_short <- get_tick_usage();
					map<string, float> short_energy <- get_tick_energy();
					loop mode over: short_energy.keys {
						if (tick_trip_energy[mode] = nil) {
							tick_trip_energy[mode] <- 0.0;
						}

						tick_trip_energy[mode] <- short_energy[mode];
					}

				}

			}

			loop mode over: tick_usage_long.keys {
				transport_usage[mode] <- tick_usage_long[mode];
			}

			loop mode over: tick_usage_short.keys {
				transport_usage[mode] <- tick_usage_short[mode];
			}

			ask transport_producer {
				do reset_tick_counters;
			}

		}

	}

	action population_activity (list<human> pop) {
	// calculate trip numbers based on population
	// TODO : modify to get the population from demography
		int nb_population <- 66352000; // population statique
		float nb_weeks_per_month <- 4.34524;
		int long_trips <- int(nb_population * (nb_weeks_per_month * long_trips_per_week));
		int short_trips <- int(nb_population * (nb_weeks_per_month * short_trips_per_week));

		// reset and process trips
		if (long != nil) {
			ask long {
				do reset_tick_counters();
				if (do_long_trips) {
					do process_long_trips(long_trips);
				}

			}

		}

		if (short != nil) {
			ask short {
				do reset_tick_counters();
				do process_short_trips(short_trips);
			}

		}

		ask pop {
			ask myself.consumer {
				do consume(myself);
			}

		}

		ask transport_consumer {
			ask transport_producer {
				loop c over: myself.consumed.keys {
					do produce(self.name, [c::myself.consumed[c]]);
				}

			}

		}

	}

	action update_transport_available {
		ask long_trip {
			ask my_taxis {
				do update_available(km_per_tick["taxi"], transport(myself.host));
			}

			ask my_ters {
				do update_available(km_per_tick["ter"], transport(myself.host));
			}

			ask my_tgvs {
				do update_available(km_per_tick["tgv"], transport(myself.host));
			}

		}

		ask short_trip {
			ask my_minibuses {
				do update_available(km_per_tick["minibus"], transport(myself.host));
			}

			ask my_bikes {
				do update_available(km_per_tick["bike"], transport(myself.host));
			}

		}

	}

	species transport_producer parent: production_agent {
		map<string, bloc> external_producers <- []; // external producers that provide the needed resources
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		map<string, float> get_tick_inputs_used {
			return tick_resources_used;
		}

		map<string, float> get_tick_outputs_produced {
			return tick_production;
		}

		map<string, float> get_tick_emissions {
			return tick_emissions;
		}

		action reset_tick_counters { // reset impact counters
			loop u over: production_inputs_T {
				tick_resources_used[u] <- 0.0; // reset resources usage
			}

			loop p over: production_outputs_T {
				tick_production[p] <- 0.0; // reset productions
			}

			loop e over: production_emissions_T {
				tick_emissions[e] <- 0.0;
			}

		}

	bool produce(string buyer, map<string,float> demand) {
	    bool ok_trips <- true;
	    
	    // fabrication
	    loop c over: demand.keys {
	        if (production_outputs_inputs_T.keys contains c) { 
	            loop u over: production_inputs_T {
	                float qty <- (production_outputs_inputs_T[c].keys contains u) ? production_outputs_inputs_T[c][u] * demand[c] : 0.0;
	                tick_resources_used[u] <- tick_resources_used[u] + qty;
	                
	                if (external_producers.keys contains u) {
	                    // demande 
	                    bool av <- external_producers[u].producer.produce(buyer, [u::qty]);
	                    if not av { write "/!\\ ÉCHEC CRITIQUE FABRICATION : " + c; }
	                }
	                tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + qty * production_output_emissions_T[c]["gCO2e emissions"];
	            }
	            tick_production[c] <- tick_production[c] + demand[c];
	        }
	        
	    }
	
	    loop c over: demand.keys {
	        if (production_trips contains c) {
	            loop u over: production_inputs_T {
	                float qty_trip <- tick_trip_energy[c];
	                if (external_producers.keys contains u) {
	                    bool av <- external_producers[u].producer.produce(buyer, [u::qty_trip]);
	                    if not av {
	                        ok_trips <- false;
	                        if (do_long_trips) { do_long_trips <- false; } 
	                        else if (do_short_trips) { do_short_trips <- false; }
	                    } else {
	                        // Récupération 
	                        if (!do_short_trips) { do_short_trips <- true; }
	                        else if (!do_long_trips) { do_long_trips <- true; }
	                        tick_resources_used[u] <- tick_resources_used[u] + qty_trip;
	                    }
	                }
	            }
	        }
	    }
	    return ok_trips;
	}
		action set_supplier(string product, bloc bloc_agent){
			write name +": external producer " + bloc_agent + " set for " + product;
			external_producers[product] <- bloc_agent;
		}

	}

	species transport_consumer parent: consumption_agent {
		map<string, float> consumed <- [];
		map<string, float> get_tick_consumption {
			return copy(consumed);
		}

		init {
			loop c over: production_outputs_T {
				consumed[c] <- 0;
			}

			consumed["trip_tgv"] <- 0.0;
			consumed["trip_ter"] <- 0.0;
			consumed["trip_taxi"] <- 0.0;
			consumed["trip_minibus"] <- 0.0;
			consumed["trip_truck"] <- 0.0;
		}

		action reset_tick_counters { // reset choices counters
			loop c over: consumed.keys {
				consumed[c] <- 0;
			}

		}

		action consume (human h) {
			ask transport(host).long {
				map<string, float> trips <- get_tick_energy();
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
				map<string, float> trips <- get_tick_energy();
				if (trips contains_key "trip_minibus") {
					myself.consumed["trip_minibus"] <- myself.consumed["trip_minibus"] + trips["trip_minibus"];
				}

			}

		}

	}

	action add_inter_city_links {
	// connect main cities between each other
		loop i from: 0 to: length(main_cities) - 1 {
			main_city city_i <- main_cities[i];
			// find 2-3 closest cities
			list<main_city> nearest_cities <- main_cities where (each != city_i) sort_by (each.location distance_to city_i.location);
			loop j from: 0 to: min([2, length(nearest_cities) - 1]) {
				main_city city_j <- nearest_cities[j];
				// take a mini-city of each constellations
				mini_city mini_i <- one_of(mini_city where (each.parent_city = city_i));
				mini_city mini_j <- one_of(mini_city where (each.parent_city = city_j));
				if mini_i != nil and mini_j != nil and !link_exists(mini_i, mini_j) {
					create transport_link {
						node_a <- mini_i;
						node_b <- mini_j;
						shape <- line([mini_i.location, mini_j.location]);
						length <- shape.perimeter / 1000;
						link_origin <- "inter_city";
						link_type <- myself.determine_link_type(mini_i, mini_j);
						max_capacity <- (link_type = "highway") ? max_capacity_highway : ((link_type = "main_road") ? max_capacity_main_road : max_capacity_local_road);
					}

				}

			}

		}

	}

	bool highway_exists (mini_city a, mini_city b) {
		main_city parent_a <- a.parent_city;
		main_city parent_b <- b.parent_city;
		bool exists <- false;
		loop mA over: parent_a.mini_cities_list {
			loop mB over: parent_b.mini_cities_list {
				if (link_exists(mA, mB)) {
					transport_link l <- get_link(mA, mB);
					if (l.link_type = "highway") {
						exists <- true;
						break;
					}

				}

			}

		}

		return exists;
	}

	/*
     * TODO: the type of the link is determined by an arbitrary length value
     * research data to decide of the type if findable
     */
	action determine_link_type (mini_city a, mini_city b) type: string {
		float distance <- a.location distance_to b.location;
		if distance > min_length_highway {
			return "highway";
		} else if distance > min_length_main_road {
			return "main_road";
		} else {
			return "local_road";
		}

	}
	/*
     * Test if a link between two mini-cities exists
     */
	bool link_exists (mini_city a, mini_city b) {
		return !(empty(transport_link where ((each.node_a = a and each.node_b = b) or (each.node_a = b and each.node_b = a))));
	}

	action get_link (mini_city a, mini_city b) type: transport_link {
		if link_exists(a, b) {
			return first(transport_link where ((each.node_a = a and each.node_b = b) or (each.node_a = b and each.node_b = a)));
		}

	}

	species long_trip {
		map<string, float> long_trip_decisions_france_data <- ["trip_tgv"::0.01845, "trip_ter"::0.13205, "trip_taxi"::0.8495]; // pas utilisé
		map<string, float> long_trip_decisions_ecotopia <- ["trip_tgv"::0.30, "trip_ter"::0.60, "trip_taxi"::0.1];
		map<string, float> max_trip_all <- ["trip_tgv"::0, "trip_ter"::0, "trip_taxi"::0];
		float avg_long_trip_distance <- 300.0; // average distance for long trips

		// tick statistics
		map<string, float> tick_trips_by_mode <- ["trip_tgv"::0.0, "trip_ter"::0.0, "trip_taxi"::0.0];
		map<string, float> tick_energy_consumption <- ["trip_tgv"::0.0, "trip_ter"::0.0, "trip_taxi"::0.0];
		map<string, float> trip_usage_by_mode <- ["trip_tgv"::0, "trip_ter"::0, "trip_taxi"::0];

		action process_long_trips (int trip_number) {
		//write 'available :';
			ask my_taxis {
				int capacity <- ref_vehicle.max_passenger_capacity;
				int current_number <- number_available;
				//write 'taxi';
				//write current_number;
				int max_trip_v <- max_trips_per_tick; // per vehicule
				myself.max_trip_all['trip_taxi'] <- current_number * max_trip_v * capacity; // max trip pour tout les vehicules de ce type (en nombre de passagers)

			}

			ask my_ters {
				int capacity <- ref_vehicle.max_passenger_capacity;
				int current_number <- number_available;
				//write 'ter';
				//write current_number;
				int max_trip_v <- max_trips_per_tick; // per vehicule
				myself.max_trip_all['trip_ter'] <- current_number * max_trip_v * capacity; // max trip pour tout les vehicules de ce type
			}

			ask my_tgvs {
				int capacity <- ref_vehicle.max_passenger_capacity;
				int current_number <- number_available;
				//write 'tgv';
				//write current_number;
				int max_trip_v <- max_trips_per_tick; // per vehicule
				myself.max_trip_all['trip_tgv'] <- current_number * max_trip_v * capacity; // max trip pour tout les vehicules de ce type
			}
			// distribute trips according to probabilities
			float next_mode <- 0.0;
			loop mode over: long_trip_decisions_ecotopia.keys { // order of priority
			// max entre nombre de personne à déplacer et nombre de personne possible à déplacer
				float mode_trips <- max(min(trip_number * long_trip_decisions_ecotopia[mode] + next_mode, max_trip_all[mode]), 0.0);
				if (mode_trips = max_trip_all[mode]) {
					next_mode <- (trip_number * long_trip_decisions_ecotopia[mode] + next_mode) - mode_trips; // passagers restants
				}
				// pour avoir le nombre de trajet non réalisés faire trip*long - max_trip_all
				float ratio_used;
				if (max_trip_all[mode] > 0) {
					ratio_used <- mode_trips / max_trip_all[mode];
				} else if (mode_trips > 0) {
					ratio_used <- 1.0; // fully saturated
				} else {
					ratio_used <- 0.0;
				}

				tick_trips_by_mode[mode] <- tick_trips_by_mode[mode] + mode_trips;
				trip_usage_by_mode[mode] <- ratio_used;
			}
			/*write "long_trip_usage";
			write "tick trips";
			write tick_trips_by_mode;
			write "tick usage ratio";
			write trip_usage_by_mode;
			write "tick max trips";
			write max_trip_all;*/
			next_mode <- 0.0;
			// process energy consumption for each mode
			ask my_tgvs {
				float nb_trips <- myself.tick_trips_by_mode["trip_tgv"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_tgv <- nb_trips / passengers_per_trip;
				km_per_tick["tgv"] <- nb_trips_tgv * myself.avg_long_trip_distance;
				float energy_consumed <- km_per_tick["tgv"] * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["trip_tgv"] <- myself.tick_energy_consumption["trip_tgv"] + energy_consumed;
			}

			ask my_ters {
				float nb_trips <- myself.tick_trips_by_mode["trip_ter"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_ter <- nb_trips / passengers_per_trip;
				km_per_tick["ter"] <- nb_trips_ter * myself.avg_long_trip_distance;
				float energy_consumed <- km_per_tick["ter"] * ref_vehicle.consumption_per_km;
				myself.tick_energy_consumption["trip_ter"] <- myself.tick_energy_consumption["trip_ter"] + energy_consumed;
			}

			ask my_taxis {
				float nb_trips <- myself.tick_trips_by_mode["trip_taxi"];
				int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
				float nb_trips_taxi <- nb_trips / passengers_per_trip;
				km_per_tick["taxi"] <- nb_trips_taxi * myself.avg_long_trip_distance;
				float energy_consumed <- km_per_tick["taxi"] * ref_vehicle.consumption_per_km;
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

		map<string, float> get_tick_usage {
			return copy(trip_usage_by_mode);
		}

		map<string, float> get_tick_energy {
			return copy(tick_energy_consumption);
		}

	}

	species short_trip {
		map<string, float> short_trip_decisions <- ["trip_bike"::0.3, "trip_minibus"::0.2, "trip_walking"::0.5];
		map<string, float> max_trip_all <- ["trip_minibus"::0, "trip_bike"::0];
		float avg_short_trip_distance <- 4.0; // average distance for short trips

		// tick statistics
		map<string, float> tick_trips_by_mode <- ["trip_minibus"::0.0, "trip_bike"::0.0, "trip_walking"::0.0];
		map<string, float> tick_energy_consumption <- ["trip_minibus"::0.0, "trip_bike"::0.0, "trip_walking"::0.0];
		map<string, float> trip_usage_by_mode <- ["trip_minibus"::0, "trip_bike"::0];

		action process_short_trips (int trip_number) {
			ask my_minibuses {
				int capacity <- ref_vehicle.max_passenger_capacity;
				int current_number <- number_available;
				int max_trip_v <- max_trips_per_tick; // per vehicule
				myself.max_trip_all['trip_minibus'] <- current_number * max_trip_v * capacity; // max trip pour tout les vehicules de ce type
			}

			ask my_bikes {
				int capacity <- ref_vehicle.max_passenger_capacity;
				int current_number <- number_available;
				int max_trip_v <- max_trips_per_tick; // per vehicule
				myself.max_trip_all['trip_bike'] <- current_number * max_trip_v * capacity; // max trip pour tout les vehicules de ce type
			}
			// distribute trips according to probabilities
			float next_mode <- 0.0;
			loop mode over: short_trip_decisions.keys {
				if (mode != "trip_walking") {
					float mode_trips <- max(min(trip_number * short_trip_decisions[mode] + next_mode, max_trip_all[mode]), 0);
					if (mode_trips = max_trip_all[mode]) {
						next_mode <- (trip_number * short_trip_decisions[mode] + next_mode) - mode_trips; // passagers restants
					}

					float ratio_used;
					if (max_trip_all[mode] > 0) {
						ratio_used <- mode_trips / max_trip_all[mode];
					} else if (mode_trips > 0) {
						ratio_used <- 1.0; // fully saturated
					} else {
						ratio_used <- 0.0;
					}

					tick_trips_by_mode[mode] <- tick_trips_by_mode[mode] + mode_trips;
					trip_usage_by_mode[mode] <- ratio_used;
				}

			}

			next_mode <- 0.0;

			// process energy consumption for each mode
			if (do_short_trips = true) { // handles energy shortage
				ask my_minibuses {
					float nb_trips <- myself.tick_trips_by_mode["trip_minibus"];
					int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
					float nb_trips_minibus <- nb_trips / passengers_per_trip;
					km_per_tick["minibus"] <- nb_trips_minibus * myself.avg_short_trip_distance;
					float energy_consumed <- (km_per_tick["minibus"] / passengers_per_trip) * ref_vehicle.consumption_per_km;
					myself.tick_energy_consumption["trip_minibus"] <- myself.tick_energy_consumption["trip_minibus"] + energy_consumed;
				}

				ask my_bikes {
					float nb_trips <- myself.tick_trips_by_mode["trip_bike"];
					int passengers_per_trip <- ref_vehicle.max_passenger_capacity;
					float nb_trips_bike <- nb_trips / passengers_per_trip;
					km_per_tick["bike"] <- nb_trips_bike * myself.avg_short_trip_distance;
				}

			} else {
				ask my_minibuses {
					myself.tick_energy_consumption["trip_minibus"] <- 0.0;
				}

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

		map<string, float> get_tick_usage {
			return copy(trip_usage_by_mode);
		}

		map<string, float> get_tick_energy {
			return copy(tick_energy_consumption);
		}

	}

}

/*
 * Species transport link representing the link between cities and mini-cities created in the graph
 */
species transport_link {
	mini_city node_a;
	mini_city node_b;
	float length;
	string link_type;
	string link_origin <- "regular"; // "regular", "rewired", "inter_city"
	float max_capacity;
	float current_flow <- 0.0;

	aspect base {
		rgb link_color;
		float link_width;
		switch link_origin {
			match "regular" {
				link_color <- #lightgray;
				link_width <- 1.5;
			}

			match "inter_city" {
				link_color <- #red;
				link_width <- 3.0;
			}

		}

		draw shape color: link_color width: link_width;
	}

	aspect type {
		rgb link_color;
		switch link_type {
			match "highway" {
				link_color <- #red;
			}

			match "main_road" {
				link_color <- #orange;
			}

			match "local_road" {
				link_color <- #gray;
			}

		}

		draw shape color: link_color width: 3.0;
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

species taxi_vehicle parent: vehicle {

	init {
		name <- "taxi_vehicle";
		consumption_per_km <- 0.17;
		avg_speed <- 100.0;
		max_passenger_capacity <- 4;
	}

}

species tgv_vehicle parent: vehicle {

	init {
		name <- "tgv_vehicle";
		consumption_per_km <- 13.0;
		avg_speed <- 300.0;
		max_passenger_capacity <- 550;
	}

}

species ter_vehicle parent: vehicle {

	init {
		name <- "ter_vehicle";
		consumption_per_km <- 14.2;
		avg_speed <- 100.0;
		max_passenger_capacity <- 250;
	}

}

species minibus_vehicle parent: vehicle {

	init {
		name <- "minibus_vehicle";
		consumption_per_km <- 2.0;
		avg_speed <- 25.0;
		max_passenger_capacity <- 90;
	}

}

species bike_vehicle parent: vehicle {

	init {
		name <- "bike_vehicle";
		consumption_per_km <- 0.0;
		avg_speed <- 15.0;
		max_passenger_capacity <- 1;
	}

}

species legs_vehicle parent: vehicle {

	init {
		name <- "legs_vehicle";
		consumption_per_km <- 0.0;
		avg_speed <- 4.0;
		max_passenger_capacity <- 1;
	}

}

species truck_vehicle parent: vehicle {

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
	int max_trips_per_tick; // nombre de trajets max par mois
	float km_age; // initialisé à la mi-vie
	int km_end_of_life;
	float alpha;
	float prod_speed;
	int prod_incr <- 0;

	action update_available (float km_travelled, transport parent_transport) {
		int to_add <- 0;
		string product_name <- "";
		switch (type) {
			match "taxis" {
				to_add <- world.production_vehicules["taxi"];
				product_name <- "taxi";
			}

			match "tgvs" {
				to_add <- world.production_vehicules["tgv"];
				product_name <- "tgv";
			}

			match "ters" {
				to_add <- world.production_vehicules["ter"];
				product_name <- "ter";
			}

			match "minibuses" {
				to_add <- world.production_vehicules["minibus"];
				product_name <- "minibus";
			}

			match "bikes" {
				to_add <- world.production_vehicules["bike"];
				product_name <- "bike";
			}

		}

		if (parent_transport != nil and product_name != "") {
		    float usage <- transport_usage[world.mode_to_trip[product_name] ];
			// write type+": "+number_available;
		    // Ramp up production (si +90% d'utilisation)
		    if (usage >= 0.9) {
		        prod_incr <- prod_incr + 1; //max( 10, prod_incr + 1);
		    } 
		    if (usage < 0.9) { 
		    	 prod_incr <-   max(-5, prod_incr - 1);
		    }
		    if (usage < 0.7) { 
		    	 prod_incr <-   0;
		    }
		    
		    to_add <- max(0, to_add + int(to_add * prod_speed *  prod_incr));
		}
		
	    if (to_add > 0 and parent_transport != nil and parent_transport.producer != nil) {
	        ask parent_transport.producer {
	            do produce(name, [product_name :: float(to_add)]);
	        }
	        
	        float old_total_km <- km_age * number_available;
	        number_available <- number_available + to_add;
	        km_age <- old_total_km / number_available;
	
	        //write type + ": Added " + to_add + " new vehicles. Total: " + number_available + ", New avg km_age: " + km_age;
	        //write type + " : " + to_add;
	    }
	
	    if (number_available > 1 and km_travelled > 0) {
	        km_age <- km_age + km_travelled / number_available;
	
	            float excess_ratio <- ((km_age - km_end_of_life) / km_end_of_life)  ^ alpha;
	            int detruit <- int(number_available * excess_ratio * 0.1);
	
	            detruit <- min(detruit, number_available - max(1, int(0.1 * number_available)));
	            
	            if (detruit > 0) {
	                number_available <- number_available - detruit;
	                // write type + ": DESTROYED " + detruit;
	
	                if(number_available > 0) {
	                    km_age <- km_age * 0.95;
	                }
	            }
	    }
	}

}

species taxis parent: transport_mode {

	init {
		type <- "taxis";
		// number_available <- 45000;
		number_available <- 1314590;
		create taxi_vehicle number:1;
		ref_vehicle <- first(taxi_vehicle);
		max_trips_per_tick <- vehicle_max_trips["taxi"];
		km_age <- 100000.0;
		km_end_of_life <- 200000;
		alpha <- 6.0;
		prod_speed <- 0.4; // Mass production, fast
	}

}

species tgvs parent: transport_mode {

	init {
		type <- "tgvs";
		// number_available <- 450;
		number_available <- 298;
		create tgv_vehicle number:1;
		ref_vehicle <- first(tgv_vehicle);
		max_trips_per_tick <- vehicle_max_trips["tgv"];
		km_age <- 7500000.0;
		km_end_of_life <- 18000000;
		alpha <- 6.0;
		prod_speed <- 0.02; // Very slow 
	}

}

species ters parent: transport_mode {

	init {
		type <- "ters";
		// number_available <- 2500;
		number_available <- 8805;
		create ter_vehicle;
		ref_vehicle <- first(ter_vehicle);
		max_trips_per_tick <- vehicle_max_trips["ter"];
		km_age <- 5000000.0;
		km_end_of_life <- 12000000;
		alpha <- 6.0;
		prod_speed <- 0.08; // Slow (heavy rolling stock)
	}

}

species minibuses parent: transport_mode {

	init {
		type <- "minibuses";
		// number_available <- 28000;
		number_available <- 52642;
		create minibus_vehicle;
		ref_vehicle <- first(minibus_vehicle);
		max_trips_per_tick <- vehicle_max_trips["minibus"];
		km_age <- 500000.0;
		km_end_of_life <- 1200000;
		alpha <- 6.0;
		prod_speed <- 0.3; // Moderate 
	}

}

species bikes parent: transport_mode {

	init {
		type <- "bikes";
		// number_available <- 3500000;
		number_available <- 48044;
		create bike_vehicle number:1;
		ref_vehicle <- first(bike_vehicle);
		max_trips_per_tick <- vehicle_max_trips["bike"];
		km_age <- 25500.0;
		km_end_of_life <- 70000;
		alpha <- 6.0;
		prod_speed <- 0.8; // Very fast 
	}

}

species trucks parent: transport_mode {
	truck_vehicle truck <- nil;

	init {
		type <- "trucks";
		number_available <- 305800;
		create truck_vehicle number: 1;
		ref_vehicle <- first(truck_vehicle);
		max_trips_per_tick <- vehicle_max_trips["truck"];
		km_age <- 612500.0;
		km_end_of_life <- 1500000;
		alpha <- 6.0;
		prod_speed <- 0.15;
	}

}

species legs parent: transport_mode {

	init {
		type <- "legs";
		number_available <- nil;
		create legs_vehicle number: 1;
		ref_vehicle <- first(legs_vehicle);
		max_trips_per_tick <- 3;
		alpha <- 6.0;
		prod_speed <- 0.0;
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

	reflex save_results {
		loop c over: production_outputs_T {
            save
                [cycle, c, tick_pop_consumption_T[c]]
            to: "results_files/transport/transport_consumption.csv" format: "csv" rewrite: false; // Pensez à supprimer les anciens fichiers entre deux experiments
        }
        loop c over: production_outputs_T {
            save
                [cycle, c, tick_production_T[c]]
            to: "results_files/transport/transport_production.csv" format: "csv" rewrite: false;
        }
        loop r over: production_inputs_T {
            save
                [cycle, r, tick_resources_used_T[r]]
            to: "results_files/transport/transport_ressources.csv" format: "csv" rewrite: false;
        }
//        loop e over: production_emissions_T {
//            save
//                [cycle, e, tick_emissions_T[e]]
//            to: "results_files/transport/transport_emissions.csv" format: "csv" rewrite: false;
//        }
        loop mode over: long_transport {
            save
                [cycle, mode, tick_long_trips[mode]]
            to: "results_files/transport/transport_long_trips.csv" format: "csv" rewrite: false;
        }
        loop mode over: short_transport {
            save
                [cycle, mode, tick_short_trips[mode]]
            to: "results_files/transport/transport_short_trips.csv" format: "csv" rewrite: false;
        }
        loop mode over: transport_name {
            save
                [cycle, mode, tick_trip_energy[mode]]
            to: "results_files/transport/transport_trip_energy.csv" format: "csv" rewrite: false;
        }
	}

	output {
		display Transport_information type: 2d{
			chart "Energy consumption by mode" type: series size: {0.5,0.5} position: {0, 0.5} {
				data "trip_minibus" value: tick_trip_energy["trip_minibus"] color: #red;
				data "trip_tgv" value: tick_trip_energy["trip_tgv"] color: #blue;
				data "trip_ter" value: tick_trip_energy["trip_ter"] color: #green;
				data "trip_taxi" value: tick_trip_energy["trip_taxi"] color: #yellow;
			    //loop mode over: transport_name {
	    			//data mode value: tick_trip_energy[mode];
	    		//}
			    data "total" value: tick_resources_used_T["kWh energy"] color: #pink;
			}
			chart "Number of long trips by mode" type: series size: {0.5,0.5} position: {0, 0} {
				data "trip_tgv" value: tick_long_trips["trip_tgv"] color: #blue;
				data "trip_ter" value: tick_long_trips["trip_ter"] color: #green;
				data "trip_taxi" value: tick_long_trips["trip_taxi"] color: #yellow;
	    		//loop mode over: long_transport {
	    			//data mode value: tick_long_trips[mode];
	    		//}
	    	}
//	    	chart "Number of short trips by mode" type: series size: {0.5,0.5} position: {0.5, 0} {
//	    		loop mode over: short_transport {
//	    			data mode value: tick_short_trips[mode];
//	    		}
//	    	}
	    	chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
	    		loop e over: production_emissions_T{
	    			data e value: tick_emissions_T[e] color: #black;
	    		}
			}
			/*
			chart "Transport usage (%)" type: series size: {0.5,0.5} position: {0.5,0.5} {
			    loop mode over: transport_usage_keys{
			        // On envoie 'nil' si le cycle est inférieur à 2, ce qui empêche le tracé
			        data mode value: transport_usage[mode] * 100;
			    }
			}
			*/
//	    	chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
//			    loop c over: production_outputs_T{
//			    	data c value: tick_pop_consumption_T[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
//			    }
//			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
				data "minibus" value: tick_production_T["minibus"] color: #red;
				data "tgv" value: tick_production_T["tgv"] color: #blue;
				data "ter" value: tick_production_T["ter"] color: #green;
				data "taxi" value: tick_production_T["taxi"] color: #yellow;
				data "truck" value: tick_production_T["truck"] color: #purple;
			    //loop c over: production_outputs_T{
			    	//data c value: tick_production_T[c];
			    //}
			}
	    }
	}

}