/**
* Name: Agricultural bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/
model Agricultural

import "../API/API.gaml"

/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global {

/* Setup */
	list<string> production_outputs_A <- ["kg_meat", "kg_vegetables", "kg_cotton"];
	list<string> production_inputs_A <- ["L water", "kWh energy", "m² land"];
	list<string> production_emissions_A <- ["gCO2e emissions"];
	int pop_size <- 1000000;	// number of agents
	int prop_human <- 70;		// number of human an agent represents
	int tick_counter <- 0; // track month 
	float total_surface_used_A <- 0.0;
	
	/* Gibiers par mois moyenne : 13442208.3kg (9,8%) */
	float kg_sanglier <- 900000 * 150.0 / 12; // Un sanglier européen pèse environ 150 kg
	float kg_cerf <- 90000 * 150.0 / 12;
	float kg_chevreuil <- 600000 * 20.0 /12;
	float kg_chamois <- 12000 * 40.0 /12 ;
	float kg_isard <- 3000 * 30.0 /12;
	float kg_mouflon <- 3000 * 37.5 /12;
	float kg_daim <- 2000 * 60.0 /12 ;
	float kg_csika <- 80 * 50.0 /12;
	float kg_gibier_monthly <- kg_sanglier + kg_cerf + kg_chevreuil + kg_chamois + kg_isard + kg_mouflon + kg_daim + kg_csika ;

	/* Production data */
	map<string, map<string, float>>
	production_output_inputs_A <- [
		"kg_meat"::["L water"::550.0, "kWh energy"::6.31, "m² land"::25.0, "gCO2e emissions"::9000.0], 
		"kg_vegetables"::["L water"::322.0, "kWh energy"::0.86, "m² land"::0.6, "gCO2e emissions"::210.0], 
		"kg_cotton"::["L water"::6000.0, "kWh energy"::0.5, "m² land"::15.0, "gCO2e emissions"::6600.0]
	];
	map<string, map<string, float>>
	production_output_emissions_A <- [
		"kg_meat"::["gCO2e emissions"::9000.0], 
		"kg_vegetables"::["gCO2e emissions"::210.0], 
		"kg_cotton"::["gCO2e emissions"::6600.0]
	];

	// kg produced per m² 
	map<string, float> kg_per_m2 <- ["kg_meat"::0.04, "kg_vegetables"::1.67, "kg_cotton"::0.066];

	/* Seasonal multipliers */
	/* Seasons: 0-2=Winter, 3-5=Spring, 6-8=Summer, 9-11=Autumn */
	// data to check to adjust for meat
	map<string, list<float>> season_multipliers <- [
		"kg_meat"::[0.85, 0.85, 0.85, 1.0, 1.0, 1.0, 1.15, 1.15, 1.15, 1.0, 1.0, 1.0], 
		"kg_vegetables"::[0.5, 0.5, 0.8, 0.8, 1.2, 1.3, 1.4, 1.3, 1.2, 1.0, 0.7, 0.6]    
	];
	
	/* Climate variability parameters */
	float climate_min <- 0.7;
	float climate_max <- 1.3;

	/* Consumption data */
	map<string, float> indivudual_consumption_A <- ["kg_meat"::2 * prop_human, "kg_vegetables"::15 * prop_human]; // monthly consumption per individual of the population
	float surface_veg_A <- indivudual_consumption_A["kg_vegetables"] * pop_size * production_output_inputs_A["kg_vegetables"]["m² land"];
	float surface_meat_A <- indivudual_consumption_A["kg_meat"] * pop_size * production_output_inputs_A["kg_meat"]["m² land"];

	/* Counters & Stats */
	map<string, float> tick_production_A <- [];
	map<string, float> tick_pop_consumption_A <- [];
	map<string, float> tick_resources_used_A <- [];
	map<string, float> tick_emissions_A <- [];
	float stock_veg_A <- 0.0;
	float stock_meat_A <- 0.0;

	init { // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0) {
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}

	}

}

/**
 * We define here the agricultural bloc as a species.
 * We implement the methods of the API.
 * We also add methods specific to this bloc to consumption behavior of the population.
 */
species agricultural parent: bloc {
	string name <- "agricultural";
	agri_producer producer <- nil;
	agri_consumer consumer <- nil;
	
	/* ----- MICRO VAR ----- */
	list<farm> farms_list;
	float max_farm_surface_m2 <- 35.0 * 1e4; //taille moyenne en france 70 ha 2020
	float min_farm_surface_m2 <- 5.0 * 1e4;
	
	// Farm distribution parameters
    float meat_farm_ratio <- 0.12;
    float veg_farm_ratio <- 0.48;
    float mixed_farm_ratio <- 0.25;
    float cotton_farm_ratio <- 0.15;

	action setup {
		list<agri_producer> producers <- [];
		list<agri_consumer> consumers <- [];
		create agri_producer number: 1 returns: producers; // instanciate the agricultural production handler
		create agri_consumer number: 1 returns: consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
		
		/* Création initiale des farms */
		do calculate_initial_farms;
	}

	action tick (list<human> pop) {
		do collect_last_tick_data();
		do population_activity(pop);
		if (tick_counter = 11) {
			tick_counter <- 0;
		} else {
			tick_counter <- tick_counter + 1;
		}

		pop_size <- length(pop);
	}

	action set_external_producer (string product, bloc bloc_agent) {
		ask producer {
			do set_supplier(product, bloc_agent);
		}

	}

	production_agent get_producer {
		return producer;
	}

	list<string> get_output_resources_labels {
		return production_outputs_A;
	}

	list<string> get_output_resources_labels {
		return production_outputs_A;
	}

	list<string> get_input_resources_labels {
		return production_inputs_A;
	}

	list<string> get_emissions_labels {
		return production_emissions_A;
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_pop_consumption_A <- consumer.get_tick_consumption(); // collect consumption behaviors
			tick_resources_used_A <- producer.get_tick_inputs_used(); // collect resources used
			//tick_production_A <- producer.get_tick_outputs_produced(); // collect production
			tick_emissions_A <- producer.get_tick_emissions(); // collect emissions
			stock_meat_A <- producer.get_stock_meat(); // collect meat stock
			stock_veg_A <- producer.get_stock_veg(); // collect vegetables stock
			surface_veg_A <- producer.get_surface_veg();
			surface_meat_A <- producer.get_surface_meat();
			
			// Produce from land using surface allocated in previous tick
			// This must be called BEFORE reset_tick_counters to use the accumulated surface
			ask agri_producer {
				do produce_from_land();
			}
			
			// Collect production AFTER produce_from_land updates it, BEFORE reset
			tick_production_A <- producer.get_tick_outputs_produced();
			
			ask agri_consumer { // prepare new tick on consumer side
				do reset_tick_counters;
			}

			ask agri_producer { // prepare new tick on producer side
				do reset_tick_counters;
			}

		}

	}

	action population_activity (list<human> pop) {
		ask pop { // execute the consumption behavior of the population
			ask myself.agri_consumer {
				do consume(myself); // individuals consume agricultural goods
			}
		}

		ask agri_consumer { // produce the required quantities
			ask agri_producer {
				loop c over: myself.consumed.keys {
					bool ok <- produce([c::myself.consumed[c]]); // send the demands to the producer
					if ok {
						float quantity_consumed <- myself.consumed[c];
						if (c = "kg_meat") {
							stock_meat <- stock_meat - quantity_consumed;
						} else if (c = "kg_vegetables") {
							stock_veg <- stock_veg - quantity_consumed;
						}

					}

				}

			}

		}

	}
	
	
	// ----- actions for init creation of farms -----
	
	action calculate_initial_farms {
        float monthly_meat_demand_total <- indivudual_consumption_A["kg_meat"] * pop_size;
        float monthly_meat_demand_farms <- max(0, monthly_meat_demand_total - kg_gibier_monthly);
        float monthly_veg_demand <- indivudual_consumption_A["kg_vegetables"] * pop_size;
        float init_monthly_cotton_demand <- 50000 * 1e3; // hypothèse : init de 50 000 tonnes
        
        // Calculate surface needed (with safety margin of 20%)
        float safety_margin <- 1.2;
        float surface_needed_meat <- monthly_meat_demand_farms * production_output_inputs_A["kg_meat"]["m² land"] * safety_margin;
        float surface_needed_veg <- monthly_veg_demand * production_output_inputs_A["kg_vegetables"]["m² land"] * safety_margin;
        float surface_needed_cotton <- init_monthly_cotton_demand * production_output_inputs_A["kg_cotton"]["m² land"] * safety_margin;
        float total_surface_needed <- surface_needed_meat + surface_needed_veg + surface_needed_cotton;
        
        // Calculate number of farms needed
        int nb_farms_needed <- int(ceil(total_surface_needed / max_farm_surface_m2));
        
        // Ensure minimum number of farms for diversity
        if (nb_farms_needed < 4) {
            nb_farms_needed <- 4;
        }
        
        write "Agricultural setup: Creating " + nb_farms_needed + " farms";
        write "  - Total surface needed: " + total_surface_needed + " m²";
        write "  - Meat demand: " + monthly_meat_demand_total + " kg/month";
        write "    - Origin farms: " + round((monthly_meat_demand_farms/monthly_meat_demand_total) * 100) + " %";
        write "    - Origin gibier: " + round((kg_gibier_monthly/monthly_meat_demand_total) * 100) + " %";
        write "  - Vegetables demand: " + monthly_veg_demand + " kg/month";
        
        // Create farms with appropriate types and sizes
        do create_initial_farms(nb_farms_needed, surface_needed_meat, surface_needed_veg, surface_needed_cotton);
    }

    action create_initial_farms(int nb_farms, float meat_surface, float veg_surface, float cotton_surface) {
        // Calculate number of each farm type
        int nb_meat_farms <- int(ceil(nb_farms * meat_farm_ratio));
        int nb_veg_farms <- int(ceil(nb_farms * veg_farm_ratio));
		int nb_cotton_farms <- int(ceil(nb_farms * cotton_farm_ratio));
        int nb_mixed_farms <- nb_farms - nb_meat_farms - nb_veg_farms - nb_cotton_farms;
        
        // Ensure at least one of each type
        if (nb_meat_farms = 0) { nb_meat_farms <- 1; }
        if (nb_veg_farms = 0) { nb_veg_farms <- 1; }
        if (nb_cotton_farms = 0) { nb_cotton_farms <- 1; }
        
        // Create meat farms
        list<farm> created_farms <- [];
        float surface_per_meat_farm <- meat_surface / nb_meat_farms;
        create farm number: nb_meat_farms with: [
            farm_type::"meat",
            surface_m2::min(surface_per_meat_farm, max_farm_surface_m2)
        ] returns: created_farms;
        farms_list <- farms_list + created_farms;
        
        // Create vegetable farms
        float surface_per_veg_farm <- veg_surface / nb_veg_farms;
        create farm number: nb_veg_farms with: [
            farm_type::"vegetables",
            surface_m2::min(surface_per_veg_farm, max_farm_surface_m2)
        ] returns: created_farms;
        farms_list <- farms_list + created_farms;
        
        // Create cotton farms
        float surface_per_cotton_farm <- cotton_surface / nb_cotton_farms;
        create farm number: nb_cotton_farms with: [
        	farm_type::"cotton",
        	surface_m2::min(surface_per_cotton_farm, max_farm_surface_m2)
        ] returns: created_farms;
        farms_list <- farms_list + created_farms;
        
        // Create mixed farms
        if (nb_mixed_farms > 0) {
            float avg_surface <- (max_farm_surface_m2 + min_farm_surface_m2) / 2;
            create farm number: nb_mixed_farms with: [
                farm_type::"mixed",
                surface_m2::avg_surface
            ] returns: created_farms;
            farms_list <- farms_list + created_farms;
        }
        
        write "Farms created: " + nb_meat_farms + " meat, " + nb_veg_farms + " vegetables, " + nb_cotton_farms + " cotton, "+ nb_mixed_farms + " mixed";
        write "Total farms: " + length(farms_list);
    }

	/**
	 * We define here the production agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is very simple here : for each behavior, we apply an average resource consumption and emissions.
	 * Some of those resources can be provided by other blocs (external producers).
	 */
	species agri_producer parent: production_agent {
		map<string, bloc> external_producers; // external producers that provide the needed resources
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		float stock_veg <- 0.0;
		float stock_meat <- 0.0;
		float surface_veg <- 0.0;
		float surface_meat <- 0.0;

		init {
			external_producers <- []; // external producers that provide the needed resources
		}

		map<string, float> get_tick_inputs_used {
			return tick_resources_used;
		}

		map<string, float> get_tick_outputs_produced {
			return tick_production;
		}

		map<string, float> get_tick_emissions {
			return tick_emissions;
		}

		float get_stock_veg {
			return stock_veg;
		}

		float get_stock_meat {
			return stock_meat;
		}

		float get_surface_veg {
			return surface_veg;
		}

		float get_surface_meat {
			return surface_meat;
		}

		action set_supplier (string product, bloc bloc_agent) {
			write name + ": external producer " + bloc_agent + " set for " + product;
			external_producers[product] <- bloc_agent;
		}
		
		// Calculate monthly production based on allocated surface and seasonal/climate factors
		action produce_from_land{
			loop c over: production_outputs_A{
				float surface <- 0.0;
				if (c = "kg_meat") {
					surface <- surface_meat;
				} else if (c = "kg_vegetables") {
					surface <- surface_veg;
				}

				// Calculate actual yield with seasonal factors and climate variability
				if (c = "kg_meat" or c = "kg_vegetables"){
					float actual_production <- calculate_yield(c, surface);
				
				
					// Add production to stock
					if (c = "kg_meat") {
						stock_meat <- stock_meat + actual_production;
					} else if (c = "kg_vegetables") {
						stock_veg <- stock_veg + actual_production;
					}
	
					tick_production[c] <- tick_production[c] + actual_production;
				}
			}

		}

		action reset_tick_counters { // reset impact counters
			loop u over: production_inputs_A {
				tick_resources_used[u] <- 0.0; // reset resources usage
			}

			loop p over: production_outputs_A {
				tick_production[p] <- 0.0; // reset productions
			}

			loop e over: production_emissions_A {
				tick_emissions[e] <- 0.0;
			}
			surface_veg <- 0.0;
			surface_meat <- 0.0;
		}

		/* calculate yield of a land takes into account the month and a random climate factor to represent dry or flood */
		float calculate_yield (string product_type, float surface_m2) {
			float yield <- kg_per_m2[product_type];
			int month <- tick_counter;
			write "Agri : month : "+ month;
			float season_factor <- season_multipliers[product_type][month];
			float climate_factor <- rnd(climate_min, climate_max);
			float total_yield <- surface_m2 * yield * season_factor * climate_factor;
			return total_yield;
		}

		bool produce (map<string, float> demand) {
			bool ok <- true;
			bool ok_surface <- true;
			loop c over: demand.keys {
				loop u over: production_inputs_A {
					float quantity_needed <- production_output_inputs_A[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand
					tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
					if (external_producers.keys contains u) { // if there is a known external producer for this product/good
						bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
						if (u = "m² land") {
							if av {
								if (c = "kg_vegetables") {
									surface_veg <- surface_veg + quantity_needed;
								} else if (c = "kg_meat") {
									surface_meat <- surface_meat + quantity_needed;
								}

							} else {
								ok_surface <- false;
							}

						} else {
							if not av {
								ok <- false;
								write "Ressource " + u + " refusé, quantité demandé : " + quantity_needed;
							}

						}

					} else {
					//write "not exist u = " + u;
					}
					// every year we ask surface_needed

					/*if (tick_counter=0){
						if (external_producers.keys contains u){
							bool av <- external_producers["m² land"].producer.produce(["m² land"::surface_veg+surface_meat]);
							if not av{
								ok_surface <- false;
							}else{
								float surface_veg <- surface_veg + indivudual_consumption_A["kg_vegetables"]*production_output_inputs_A["kg_vegetables"]["m² land"];
								float surface_meat <- surface_meat + indivudual_consumption_A["kg_meat"]*production_output_inputs_A["kg_meat"]["m² land"];
							}
						
						}
					}*/
				}

				loop e over: production_emissions_A { // apply emissions
					float quantity_emitted <- production_output_emissions_A[c][e] * demand[c];
					tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
				}

				/*if ok {
					if (c = "kg_meat") {
						stock_meat <- stock_meat + demand[c];
					}

					if (c = "kg_vegetables") {
						stock_veg <- stock_veg + demand[c];
					}

				}*/

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
	species agri_consumer parent: consumption_agent {
		map<string, int> consumed <- [];
		map<string, float> get_tick_consumption {
			return copy(consumed);
		}

		init {
			loop c over: production_outputs_A {
				consumed[c] <- 0;
			}

		}

		action reset_tick_counters {
			loop c over: consumed.keys { // reset choices counters
				consumed[c] <- 0;
			}

		}

		action consume (human h) {
			loop c over: indivudual_consumption_A.keys {
				consumed[c] <- consumed[c] + indivudual_consumption_A[c];
			}

		}

	}
	
}

/* ----- FARM agent for micro model ----- */
species farm {
	
	string farm_type ; //meat, vegetables, mixed, cotton
	float surface_m2;
	
	// TODO localisation on map
	// TODO supplying_cities list of cities being supplied by the farm in a way that they are not too far form each other
	
	map<string, float> production_capacity; //kg par tick tenant en compte la surface de l'exploitation
	map<string, map<string, float>> product_ressources_needed; //produit, (ressource, quantité)
	
	map<string, float> produced <- []; //type de produit, quantité
	map<string, float> emissions <- []; // type de produit, leur correspondante emssion de GES
	
	init {
		do compute_capacity;
		do compute_product_ressources_needed;
	}
	
	/* ---- Méthodes ---- */
	action compute_capacity {
		production_capacity <- [];
	
		if (farm_type = "meat") {
			production_capacity["kg_meat"] <- surface_m2 * kg_per_m2["kg_meat"];
		}
	
		if (farm_type = "vegetables") {
			production_capacity["kg_vegetables"] <- surface_m2 * kg_per_m2["kg_vegetables"];
		}
	
		if (farm_type = "cotton") {
			production_capacity["kg_cotton"] <- surface_m2 * kg_per_m2["kg_cotton"];
		}
	
		if (farm_type = "mixed") {
			production_capacity["kg_meat"] <- surface_m2 * 0.02;
			production_capacity["kg_vegetables"] <- surface_m2 * 0.8;
		}
	      
	}
	
	action compute_product_ressources_needed {
		if empty(production_capacity) {
			write "Production capacity of the farm has not been computed";
		}
		
		product_ressources_needed <-[];
		
		loop product over: production_capacity.keys {
			map<string, float> inputs_needed <- [];
			inputs_needed["L water"] <- production_output_inputs_A[product]["L water"] * production_capacity[product];
			inputs_needed["kWh energy"] <- production_output_inputs_A[product]["kWh energy"] * production_capacity[product]; //TODO check the name of input with energy bloc
			product_ressources_needed[product] <- inputs_needed;
		}
	}
	
	/* Calculates products produced and the corresponding emissions.
	 * params quota_ressources : % of ressources needed that have been given (cas pénuries) */
	action produce(float quota_ressources) {		
		produced <- [];
		emissions <- [];
	
		loop product over: production_capacity.keys {
			int month <- tick_counter;
			write "Agri : month"+ month;
			float season_factor <- season_multipliers[product][month];
			float climate_factor <- rnd(climate_min, climate_max);
			float qty;
			if quota_ressources = nil {
				qty <- production_capacity[product] * season_factor * climate_factor;
			} 
			else {
				qty <- production_capacity[product] * season_factor * climate_factor * quota_ressources;
				
			}
			produced[product] <- qty;
			
			emissions["gCO2e emissions"] <- emissions["gCO2e emissions"] + qty * production_output_emissions_A[product]["gCO2e emissions"];
		}
		
	}
	
	action get_product_ressources_needed {
		return product_ressources_needed;
	}
	
	action get_produced {
		return produced;
	}
	
	action get_emissions {
		return emissions;
	}
	
}

/**
 * We define here the experiment and the displays related to agricultural. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_agricultural type: gui {
	output {
		display Agricultural_information {
			chart "Population direct consumption" type: series size: {0.5, 0.5} position: {0, 0} {
				loop c over: production_outputs_A {
					data c value: tick_pop_consumption_A[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
				}

			}

			chart "Total production" type: series size: {0.5, 0.5} position: {0.5, 0} {
				loop c over: production_outputs_A {
					data c value: tick_production_A[c];
				}

			}

			chart "Resources usage" type: series size: {0.5, 0.5} position: {0, 0.5} {
				loop r over: production_inputs_A {
					data r value: tick_resources_used_A[r];
				}

			}

			chart "Production emissions" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				loop e over: production_emissions_A {
					data e value: tick_emissions_A[e];
				}

			}

		}

		display Stock_levels {
			chart "Stock levels" type: series {
				data "Meat stock (kg)" value: stock_meat_A color: #red;
				data "Vegetables stock (kg)" value: stock_veg_A color: #green;
			}

		}

	}

}