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
	list<string> production_perishables_A <- ["kg_meat", "kg_vegetables"];
	
	int pop_size;	// number of agents
	int prop_human;		// number of human an agent represents
	int tick_counter <- 0; // track month, we start in spring
	//float total_surface_used_A <- 0.0;

	/* Gibiers par mois moyenne : 13442208.3kg (9,8%) */
	float kg_sanglier <- 900000 * 150.0 / 12; // Un sanglier européen pèse environ 150 kg
	float kg_cerf <- 90000 * 150.0 / 12;
	float kg_chevreuil <- 600000 * 20.0 / 12;
	float kg_chamois <- 12000 * 40.0 / 12;
	float kg_isard <- 3000 * 30.0 / 12;
	float kg_mouflon <- 3000 * 37.5 / 12;
	float kg_daim <- 2000 * 60.0 / 12;
	float kg_csika <- 80 * 50.0 / 12;
	float kg_gibier_monthly <- kg_sanglier + kg_cerf + kg_chevreuil + kg_chamois + kg_isard + kg_mouflon + kg_daim + kg_csika;

	/* Production data */
	map<string, map<string, float>>
	production_output_inputs_A <- ["kg_meat"::["L water"::550.0, "kWh energy"::6.31, "m² land"::25.0, "gCO2e emissions"::9000.0], "kg_vegetables"::["L water"::322.0, "kWh energy"::0.86, "m² land"::0.6, "gCO2e emissions"::210.0], "kg_cotton"::["L water"::6000.0, "kWh energy"::0.5, "m² land"::15.0, "gCO2e emissions"::6600.0]];
	map<string, map<string, float>>
	production_output_emissions_A <- ["kg_meat"::["gCO2e emissions"::9000.0], "kg_vegetables"::["gCO2e emissions"::210.0], "kg_cotton"::["gCO2e emissions"::6600.0]];

	// kg produced per m² 
	map<string, float> kg_per_m2 <- ["kg_meat"::0.04, "kg_vegetables"::1.67, "kg_cotton"::0.066];

	/* Seasonal multipliers */
	/* Seasons: 0-2=Spring, 3-5=Summer, 6-8=Autumn, 9-11=Winter */
	// data to check to adjust for meat
	map<string, list<float>>
	season_multipliers <- ["kg_meat"::[1.0, 1.0, 1.0, 1.15, 1.15, 1.15, 1.0, 1.0, 1.0, 0.85, 0.85, 0.85], "kg_vegetables"::[0.8, 1.2, 1.3, 1.4, 1.3, 1.2, 1.0, 0.7, 0.6, 0.5, 0.5, 0.8], "kg_cotton"::[0.7, 0.9, 1.0, 1.2, 1.3, 1.5, 1.4, 0.8, 0.5, 0.3, 0.3, 0.5]];

	/* Climate variability parameters */
	float climate_min <- 0.7;
	float climate_max <- 1.3;

	/* Consumption data */
	map<string, float> individual_consumption_A <- ["kg_meat"::2, "kg_vegetables"::15]; // monthly consumption per individual of the population
	//float surface_veg_A <- individual_consumption_A["kg_vegetables"] * pop_size * production_output_inputs_A["kg_vegetables"]["m² land"];
	//float surface_meat_A <- individual_consumption_A["kg_meat"] * pop_size * production_output_inputs_A["kg_meat"]["m² land"];

	/* Counters & Stats */
	map<string, float> tick_production_A <- [];
	map<string, float> tick_pop_consumption_A <- [];
	map<string, float> tick_resources_used_A <- [];
	map<string, float> tick_emissions_A <- [];
	map<string, float> products_stock_A <- []; //"kg_meat"::0.0, "kg_vegetables"::0.0, "kg_cotton"::0.0
	map<string, float> tick_waste_A <- [];
	int total_num_farms_A <- 0;
	float total_surface_farms_A <- 0.0;

	/* To optimize number of farms */
	map<string, float> anual_pop_consumption_A <- ["kg_meat"::0.0, "kg_vegetables"::0.0];
	map<string, float> anual_production_A <- ["kg_meat"::0.0, "kg_vegetables"::0.0];

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
	float max_farm_surface_m2 <- 70.0 * 1e4; //taille moyenne en france 70 ha 2020
	float min_farm_surface_m2 <- 35.0 * 1e4;
	
	// Farm distribution parameters
	float meat_farm_ratio <- 0.25;
	float veg_farm_ratio <- 0.35;
	float mixed_farm_ratio <- 0.2;
	float cotton_farm_ratio <- 0.2;

	/* Shortage tracking (0 = no shortage; 1 = complete shortage) */
	map<string, float> food_shortage <- ["kg_meat"::0.0, "kg_vegetables"::0.0];

	action setup {
		list<agri_producer> producers <- [];
		list<agri_consumer> consumers <- [];
		create agri_producer number: 1 returns: producers; // instanciate the agricultural production handler
		create agri_consumer number: 1 returns: consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}

	/* Actions order in each tick
	 * - Collect data & reset for next tick
	 * - Production
	 * - Compute perishing products in stock
	 * - Consumption
	 * extra : update tick counter
	 */
	action tick (list<human> pop) {
		do collect_last_tick_data();
		ask agri_producer {
			do produce_from_farms(myself.farms_list);
			do update_meat_stock();
			do apply_perishing();
		}

		do population_activity(pop);
		if (tick_counter = 11) {
			do update_farms_list();
			do reset_anual_data();
		}

		if (tick_counter = 11) {
			tick_counter <- 0;
		} else {
			tick_counter <- tick_counter + 1;
		}

		pop_size <- length(pop);
		// prop_human <- round(7 * 1e7 / pop_size);
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

	//	list<string> get_output_resources_labels {
	//		return production_outputs_A;
	//	}
	list<string> get_input_resources_labels {
		return production_inputs_A;
	}

	list<string> get_emissions_labels {
		return production_emissions_A;
	}

	map<string, float> get_food_shortage {
		return food_shortage;
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_pop_consumption_A <- consumer.get_tick_consumption(); // collect consumption behaviors
			tick_resources_used_A <- producer.get_tick_inputs_used(); // collect resources used
			tick_production_A <- producer.get_tick_outputs_produced(); // collect production
			tick_emissions_A <- producer.get_tick_emissions(); // collect emissions
			products_stock_A <- producer.get_products_stock(); // collect stock
			tick_waste_A <- producer.get_tick_waste();
			if (tick_counter != 11) { // to collect anual data
				do update_anual_data_with_tick();
			}

			ask agri_consumer { // prepare new tick on consumer side
				do reset_tick_counters;
			}

			ask agri_producer { // prepare new tick on producer side
				do reset_tick_counters;
			}

		} else if (cycle = 0) { // Creates intial farms on first tick
			write "Init pop_size " + pop_size;
			write "Init prop_human " + prop_human;
			do calculate_initial_farms();
			products_stock_A <- producer.get_products_stock(); // init with stocks
		}

	}

	/* Modelises the production and consumption of products by the population */
	action population_activity (list<human> pop) {
		loop product over: food_shortage.keys {
			food_shortage[product] <- 0.0;
		}

		ask pop {
			additional_attributes["shortage_mortality_coeff"] <- "1.0";
		}

		ask pop { // execute the consumption behavior of the population
			ask myself.agri_consumer {
				do consume(myself); // individuals consume agricultural goods
			}

		}

		ask agri_consumer { // produce the required quantities
		
			//float total_meat_demand <- consumed["kg_meat"];
            //float remaining_meat_demand <- max(0, total_meat_demand - kg_gibier_monthly);
            
            agricultural agri_ref <- myself;
            float max_mortality_coef <- 1.0;
                        
			ask agri_producer {
                bool ok;
                loop c over: myself.consumed.keys {
//                	float demand_qty;
//                	if (c = "kg_meat"){
//                		demand_qty <- remaining_meat_demand;
//                		ok <- produce(["kg_meat"::remaining_meat_demand]);
//                	} else {
//                		demand_qty <- myself.consumed[c];
//                		ok <- produce([c::myself.consumed[c]]);
//                	}
                	
                	float demand_qty <- myself.consumed[c];
                	ok <- produce([c::myself.consumed[c]]);
                	
            		if not ok {
            			write "Pénurie de " + c ;
            			
            			float shortage_coef <- 0.0;
            			if (demand_qty > 0) {
            				if (products_stock[c] <= 0) {
            					shortage_coef <- 1.0;
            				} else if (products_stock[c] < demand_qty) {
            					shortage_coef <- (demand_qty - products_stock[c]) / demand_qty;
            				}
            			}
            			
            			agri_ref.food_shortage[c] <- shortage_coef;
            			
            			// Calcul new coeff (*5 to check)
            			if (shortage_coef > 0) {
            				float mortality_coef <- 1.0 + shortage_coef*5;
            				max_mortality_coef <- max([max_mortality_coef, mortality_coef]);
            			}
            		}
                }

			}
			// Apply coeff to humans
			if (max_mortality_coef > 1.0) {
				ask pop {
					additional_attributes["shortage_mortality_coeff"] <- string(max_mortality_coef);
				}

			}

		}

	}

	// ----- actions for init creation of farms -----
	action calculate_initial_farms {
		write "Pop size used for init demand " + pop_size;
		write "Prop human used for init "+ prop_human;
        float monthly_meat_demand_total <- individual_consumption_A["kg_meat"] * pop_size * prop_human;
        float monthly_meat_demand_farms <- max(0, monthly_meat_demand_total - kg_gibier_monthly);
        float monthly_veg_demand <- individual_consumption_A["kg_vegetables"] * pop_size * prop_human;
        float init_monthly_cotton_demand <- 50000 * 1e3; // hypothèse : init de 50 000 tonnes
        
        // Calculate surface needed (with safety margin of 10%)
        float safety_margin <- 1.0;
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
        write "  - Cotton demand: " + init_monthly_cotton_demand + " kg/month";
        
        // Create farms with appropriate types and sizes
        do create_initial_farms(nb_farms_needed, surface_needed_meat, surface_needed_veg, surface_needed_cotton);
    }

		// Calculate surface needed (with safety margin of 10%)
		float safety_margin <- 1.0;
		float surface_needed_meat <- monthly_meat_demand_total * production_output_inputs_A["kg_meat"]["m² land"] * safety_margin;
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
		write "    - Origin farms: " + round((monthly_meat_demand_farms / monthly_meat_demand_total) * 100) + " %";
		write "    - Origin gibier: " + round((kg_gibier_monthly / monthly_meat_demand_total) * 100) + " %";
		write "  - Vegetables demand: " + monthly_veg_demand + " kg/month";
		write "  - Cotton demand: " + init_monthly_cotton_demand + " kg/month";

		// Create farms with appropriate types and sizes
		do create_initial_farms(nb_farms_needed, surface_needed_meat, surface_needed_veg, surface_needed_cotton);
	}

	action create_initial_farms (int nb_farms, float meat_surface, float veg_surface, float cotton_surface) {
	// Calculate number of each farm type
		int nb_meat_farms <- int(round(nb_farms * meat_farm_ratio));
		int nb_veg_farms <- int(round(nb_farms * veg_farm_ratio));
		int nb_cotton_farms <- int(round(nb_farms * cotton_farm_ratio));
		int nb_mixed_farms <- nb_farms - nb_meat_farms - nb_veg_farms - nb_cotton_farms;
		if (nb_mixed_farms < 0) {
			nb_mixed_farms <- 0;
			// Réduire proportionnellement les autres
			int overflow <- abs(nb_mixed_farms);
			nb_meat_farms <- max(1, nb_meat_farms - int(overflow * meat_farm_ratio));
			nb_veg_farms <- max(1, nb_veg_farms - int(overflow * veg_farm_ratio));
		}

		// Ensure at least one of each type
		if (nb_meat_farms = 0) {
			nb_meat_farms <- 1;
		}

		if (nb_veg_farms = 0) {
			nb_veg_farms <- 1;
		}

		if (nb_cotton_farms = 0) {
			nb_cotton_farms <- 1;
		}

		if (nb_mixed_farms = 0) {
			nb_mixed_farms <- 1;
		}

		// Check if surface available for all init farms
		float total_surface_needed <- meat_surface + veg_surface + cotton_surface;
		ask agri_producer {
			if (external_producers.keys contains "m² land") {
				bool surface_granted <- external_producers["m² land"].producer.produce(self.name, ["m² land"::total_surface_needed]);
				if (not surface_granted) {
					write "ERROR " + total_surface_needed + " m² could not be allocated to initial farms";
					write "   Agricultural bloc cannot initialize properly!";
					return;
				}

			} else {
				write "ERROR: No external producer for 'm² land' configured!";
			}

		}

		// Create meat farms
		list<farm> created_farms <- [];
		float surface_per_meat_farm <- meat_surface / nb_meat_farms;
		create farm number: nb_meat_farms with: [farm_type::"meat", surface_m2::min(surface_per_meat_farm, max_farm_surface_m2)] returns: created_farms;
		farms_list <- farms_list + created_farms;

		// Create vegetable farms
		float surface_per_veg_farm <- veg_surface / nb_veg_farms;
		create farm number: nb_veg_farms with: [farm_type::"vegetables", surface_m2::min(surface_per_veg_farm, max_farm_surface_m2)] returns: created_farms;
		farms_list <- farms_list + created_farms;

		// Create cotton farms
		float surface_per_cotton_farm <- cotton_surface / nb_cotton_farms;
		create farm number: nb_cotton_farms with: [farm_type::"cotton", surface_m2::min(surface_per_cotton_farm, max_farm_surface_m2)] returns: created_farms;
		farms_list <- farms_list + created_farms;

		// Create mixed farms
		if (nb_mixed_farms > 0) {
			float avg_surface <- (max_farm_surface_m2 + min_farm_surface_m2) / 2;
			create farm number: nb_mixed_farms with: [farm_type::"mixed", surface_m2::avg_surface] returns: created_farms;
			farms_list <- farms_list + created_farms;
		}

		total_num_farms_A <- length(farms_list);
		total_surface_farms_A <- total_surface_needed;
		write "Farms created: " + nb_meat_farms + " meat, " + nb_veg_farms + " vegetables, " + nb_cotton_farms + " cotton, " + nb_mixed_farms + " mixed";
		write "Total farms: " + length(farms_list);
	}

	/* To add the pop_consumption and the production of each tick in the same year.
     * implementation for only the population concumption/production (cotton not taken into consideration)
     */
	action update_anual_data_with_tick {
		loop p over: individual_consumption_A.keys {
			anual_pop_consumption_A[p] <- anual_pop_consumption_A[p] + tick_pop_consumption_A[p];
			anual_production_A[p] <- anual_production_A[p] + tick_production_A[p];
		}

	}

	action reset_anual_data {
		loop p over: individual_consumption_A.keys {
			anual_pop_consumption_A[p] <- 0.0;
			anual_production_A[p] <- 0.0;
		}

	}

	/* Depending on production/consumption ratio we delete farms or add */
	action update_farms_list {
		map<string, float> upper_threshold <- ["kg_meat"::1.1, "kg_vegetables"::1.3];
		loop p over: individual_consumption_A.keys {
			float ratio <- anual_production_A[p] / anual_pop_consumption_A[p];

			// TODO does farm_list update itself od its contents ?
			list<farm> producing_farms <- farms_list where (each.farm_type = get_farm_type_for_product(p));
			if (ratio > upper_threshold[p]) { // over production -> change type farm or delete them
				int num_to_delete <- round(0.1 * length(producing_farms));
				//    			int half <- num_to_delete div 2;
				//    			
				//    			loop i from: 0 to: half - 1 { // first half convert to mixed
				//    				do change_farm_type(producing_farms[i], "mixed");
				//    			}
				float to_delete_surface <- 0.0;
				loop i from: 0 to: num_to_delete - 1 {
					to_delete_surface <- to_delete_surface + producing_farms[i].surface_m2;
					ask producing_farms[i] {
						do die;
					}

				}

				write "Deleting " + (-to_delete_surface) + " m2 of " + p + " farms ...";
				// TODO tell environment we're reducing our allocated surface
				ask agri_producer {
					if (external_producers.keys contains "m² land") {
						bool surface_liberated <- external_producers["m² land"].producer.produce(self.name, ["m² land"::(-to_delete_surface)]);
						if not surface_liberated {
							write "WARNING: Could not liberate " + to_delete_surface + " m² to environment";
						}

					} else {
						write "ERROR: No external producer for 'm² land' configured!";
					}

				}

				do clean_dead_farms();
			} else if (ratio < 0.95) { // under production -> create farms
				int num_to_create <- round(0.1 * length(producing_farms));
				float avg_surface <- (max_farm_surface_m2 + min_farm_surface_m2) / 2;
				float to_add_surface <- num_to_create * avg_surface;

				// check if there's available surface
				bool surface_granted <- false;
				ask agri_producer {
					if (external_producers.keys contains "m² land") {
						surface_granted <- external_producers["m² land"].producer.produce(self.name, ["m² land"::to_add_surface]);
					} else {
						write "ERROR: No external producer for 'm² land' configured!";
					}

				}

				if (not surface_granted) {
					write "ERROR " + to_add_surface + " m² could not be allocated to extra farms";
					return;
				}

				write "Adding " + to_add_surface + " m2 of " + p + " farms ...";
				create farm number: num_to_create with: [farm_type::get_farm_type_for_product(p), surface_m2::avg_surface] returns: created_farms;
				farms_list <- farms_list + created_farms;

				// update farm data
				total_num_farms_A <- length(farms_list);
				total_surface_farms_A <- total_surface_farms_A + to_add_surface;
			}

		}

	}

	action change_farm_type (farm target_farm, string new_type) {
		if (target_farm = nil or not (new_type in ["meat", "vegetables", "cotton", "mixed"])) {
			return;
		}

		ask target_farm {
			farm_type <- new_type;
			do compute_capacity;
			do compute_product_resources_needed;
		}

	}

	string get_farm_type_for_product (string product) {
		switch product {
			match "kg_meat" {
				return "meat";
			}

			match "kg_vegetables" {
				return "vegetables";
			}

			match "kg_cotton" {
				return "cotton";
			}

			default {
				return "mixed";
			}

		}

	}

	/* Checks for dead instances of farm in farms_list to remove and updates farm data */
	action clean_dead_farms {
		int initial_count <- length(farms_list);
		farms_list <- farms_list where (each != nil and not dead(each));
		int removed_count <- initial_count - length(farms_list);
		if (removed_count > 0) {
		//write "Cleaned " + removed_count + " dead farms from farms_list";
			total_num_farms_A <- length(farms_list);
			total_surface_farms_A <- farms_list sum_of (each.surface_m2);
		}

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

		/* Stock related */
		map<string, float> tick_waste <- []; // product, qty of product that perishes -> eliminated from stock
		//map<string, float> products_stock <- ["kg_meat":: 1.4 * 1e8, "kg_vegetables"::2.0 * 1e9, "kg_cotton"::50000.0 * 1e3];
		map<string, float> products_stock <- ["kg_meat"::0.0, "kg_vegetables"::0.0, "kg_cotton"::0.0];
		map<string, float> perish_rate <- ["kg_meat"::0.05, "kg_vegetables"::0.08]; //choix arbitraire


		//map<string, float> surface_used <- ["kg_meat":: 0.0, "kg_vegetables"::0.0, "kg_cotton"::0.0];
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

		map<string, float> get_products_stock {
			return products_stock;
		}

		map<string, float> get_tick_waste {
			return tick_waste;
		}

		action set_supplier (string product, bloc bloc_agent) {
			write name + ": external producer " + bloc_agent + " set for " + product;
			external_producers[product] <- bloc_agent;
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

			loop p over: production_perishables_A {
				tick_waste[p] <- 0.0;
			}

		}

		//		/* calculate yield of a land takes into account the month and a random climate factor to represent dry or flood */
		//		float calculate_yield (string product_type, float surface_m2) {
		//			float yield <- kg_per_m2[product_type];
		//			int month <- tick_counter;
		//			write "Agri : month : "+ month;
		//			float season_factor <- season_multipliers[product_type][month];
		//			float climate_factor <- rnd(climate_min, climate_max);
		//			float total_yield <- surface_m2 * yield * season_factor * climate_factor;
		//			return total_yield;
		//		}

		/* Checks if we are answering the demand with our stocks (also contains production of the tick) */
		bool produce (string buyer, map<string, float> demand) {
			bool ok <- true;
			loop c over: demand.keys {
				if (products_stock[c] >= demand[c]) {
					products_stock[c] <- products_stock[c] - demand[c];
				} else {
					ok <- false;
				}

			}

			return ok;
		}

		action produce_from_farms (list<farm> farm_list) {
			ask farms_list {
				map<string, map<string, float>> resources_needed <- get_product_resources_needed();
				float quota_received <- 1.0; //assumption for the moment that is 100% met or nothing
				loop product over: resources_needed.keys {
					loop ressource over: resources_needed[product].keys {
						float qty_needed <- resources_needed[product][ressource];
						if (myself.external_producers.keys contains ressource) {
							bool available <- myself.external_producers[ressource].producer.produce(self.name, [ressource::qty_needed]);
							if not available {
							// TODO implement partial availability (penurie case)
								quota_received <- 0.0;
								//write "PRODUCTION : Farm " + name + " " + farm_type + " cannot get " + ressource + " for " + product;
							} else {
								myself.tick_resources_used[ressource] <- myself.tick_resources_used[ressource] + qty_needed;
							}

						}

					}

				}

				do farm_produce(quota_received);
				map<string, float> farm_production <- get_produced();
				loop product over: farm_production.keys {
					myself.tick_production[product] <- myself.tick_production[product] + farm_production[product];
					myself.products_stock[product] <- myself.products_stock[product] + farm_production[product];
				}

				map<string, float> farm_emissions <- get_emissions();
				loop e over: farm_emissions.keys {
					myself.tick_emissions[e] <- myself.tick_emissions[e] + farm_emissions[e];
				}

				myself.tick_resources_used["m² land"] <- myself.tick_resources_used["m² land"] + surface_m2;
			}

		}
		
		/* Adds the constant availability of meat form gibier */
		action update_meat_stock {
			products_stock["kg_meat"] <- products_stock["kg_meat"] + kg_gibier_monthly;
		}
		
		/* Applies perishing rate to stock */
		action apply_perishing {
			loop p over: production_perishables_A {
				tick_waste[p] <- products_stock[p] * perish_rate[p];
				products_stock[p] <- products_stock[p] - tick_waste[p];
			}

		}

	}

	/**
	 * We define here the consumption agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is very simple here : each behavior as a certain probability to be selected.
	 */
	species agri_consumer parent: consumption_agent {
		map<string, float> consumed <- [];
		map<string, float> get_tick_consumption {
			return copy(consumed);
		}

		init {
			loop c over: individual_consumption_A.keys { // to not consider cotton a consumed product by population
				consumed[c] <- 0;
			}

		}

		action reset_tick_counters {
			loop c over: consumed.keys { // reset choices counters
				consumed[c] <- 0;
			}

		}

		/* Allows to set the demand of products' qty to be consumed */
		action consume (human h) {
			loop c over: individual_consumption_A.keys {
				consumed[c] <- consumed[c] + individual_consumption_A[c] * prop_human;
			}

		}

	}

}

/* ----- FARM agent for micro model ----- */
species farm {
	string farm_type; //meat, vegetables, mixed, cotton
	float surface_m2;

	// TODO localisation on map
	// TODO supplying_cities list of cities being supplied by the farm in a way that they are not too far form each other
	map<string, float> production_capacity; //kg par tick tenant en compte la surface de l'exploitation
	map<string, map<string, float>> product_resources_needed; //produit, (ressource, quantité)
	map<string, float> produced <- []; //type de produit, quantité
	map<string, float> emissions <- []; // type of emission, its qty
	init {
		do compute_capacity;
		do compute_product_resources_needed;
	}

	/* ---- Getters ---- */
	map<string, map<string, float>> get_product_resources_needed {
		return product_resources_needed;
	}

	map<string, float> get_produced {
		return produced;
	}

	map<string, float> get_emissions {
		return emissions;
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
			production_capacity["kg_meat"] <- surface_m2 * 0.2;
			production_capacity["kg_vegetables"] <- surface_m2 * 0.8;
		}

	}

	action compute_product_resources_needed {
		if empty(production_capacity) {
			write "Production capacity of the farm has not been computed";
		}

		product_resources_needed <- [];
		loop product over: production_capacity.keys {
			map<string, float> inputs_needed <- [];
			inputs_needed["L water"] <- production_output_inputs_A[product]["L water"] * production_capacity[product];
			inputs_needed["kWh energy"] <- production_output_inputs_A[product]["kWh energy"] * production_capacity[product]; //TODO check the name of input with energy bloc
			product_resources_needed[product] <- inputs_needed;
		}

	}

	/* Calculates products produced (proportionate to resources given) and the corresponding emissions.
	 * params quota_resources : % of resources needed that have been given (cas pénuries) */
	action farm_produce (float quota_resources) {
		produced <- [];
		emissions <- ["gCO2e emissions"::0.0];
		loop product over: production_capacity.keys {
			int month <- tick_counter;
			// write "Agri : month"+ month;
			float season_factor <- season_multipliers[product][month];
			float climate_factor <- rnd(climate_min, climate_max);
			float qty;
			if quota_resources = nil {
				qty <- production_capacity[product] * season_factor * climate_factor;
			} else {
				qty <- production_capacity[product] * season_factor * climate_factor * quota_resources;
			}

			produced[product] <- qty;
			emissions["gCO2e emissions"] <- emissions["gCO2e emissions"] + qty * production_output_emissions_A[product]["gCO2e emissions"];
		}

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
		monitor "Total number of farms" value: world.total_num_farms_A;
		monitor "Number of individual agents" value: pop_size;
		
		display Products_information {
			chart "Meat - Consumption vs. Production" type: series size: {0.5, 0.5} position: {0, 0} {
				data "Consumption" value: tick_pop_consumption_A["kg_meat"] color: #violet;
				data "Production" value: tick_production_A["kg_meat"] color: #turquoise;
			}

			chart "Vegetables - Consumption vs. Production" type: series size: {0.5, 0.5} position: {0.5, 0} {
				data "Consumption" value: tick_pop_consumption_A["kg_vegetables"] color: #violet;
				data "Production" value: tick_production_A["kg_vegetables"] color: #turquoise;
			}

			chart "Cotton - Production" type: series size: {0.5, 0.5} position: {0, 0.5} {
				data "Production" value: tick_production_A["kg_cotton"] color: #turquoise;
			}

			chart "Stock evolution" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				data "kg_meat" value: products_stock_A["kg_meat"] color: #red;
				data "kg_vegetables" value: products_stock_A["kg_vegetables"] color: #blue;
				data "kg_cotton" value: products_stock_A["kg_cotton"] color: #lime;
			}

		}

		display Other_information {
			chart "Population size evolution" type: series size: {0.5, 0.5} position: {0, 0} {
				data "pop_size" value: pop_size color: #magenta;
			}

			chart "Resources usage" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				data "L water" value: tick_resources_used_A["L water"] color: #skyblue;
				data "kWh energy" value: tick_resources_used_A["kWh energy"] color: #orange;
				data "m² land" value: tick_resources_used_A["m² land"] color: #pink;
			}

			chart "Production emissions" type: series size: {0.5, 0.5} position: {0.5, 0} {
				loop e over: production_emissions_A {
					data e value: tick_emissions_A[e] color: #brown;
				}

			}

			chart "Waste generated of perishable goods" type: series size: {0.5, 0.5} position: {0, 0.5} {
				loop w over: production_perishables_A {
					data w value: tick_waste_A[w];
				}

			}

		}

	}

}