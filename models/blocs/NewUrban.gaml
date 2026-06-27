/**
* Name: Urbanplanning
* Based on the internal empty template. 
* Author: williamsardon
* Tags: 
*/
model Urbanplanning

import "../API/API.gaml"
import "../blocs/Demography.gaml"

global {
/* Setup */

// Config
	float wooden_building_ratio <- 0.4;
	int min_modular_capacity <- 5;
	float factory_productivity <- 5000.0;
	float factory_per_worker <- 0.3;
	float company_per_worker <- 0.5;
	float unemployed_per_worker <- 0.076;
	int modular_lifespan <- 1200;
	int wooden_lifespan <- 1200;
	bool hazard <- false;
	
	map<string, int> max_capacity <- [
		"modular house"::	20,
		"wooden house"::	60,
		"plastic factory"::	100,
		"company"::			100,
		"leisure"::			100,
		"school"::			100
	];
	
	map<string, float> renew_proba <- [
		"modular house"::	0.0,
		"wooden house"::	0.0,
		"plastic factory"::	0.0,
		"company"::			0.0,
		"leisure"::			0.0,
		"school"::			0.0
	];
	
	map<string, float> recycled_ratio <- [
		"kg plastic"::	1.0,
		"m3_wood"::		1.0,
		"m² land"::		1.0
	];

	// TODO : adapter les productions et les ressources demandées sur les vrais variables et valeurs
	list<string> production_inputs_U <- ["m3_wood", "kg_cotton", "m² land", "kWh energy"];
	list<string> production_outputs_U <- ["modular house", "modular house extension", "wooden house", "plastic factory", "company", "leisure", "school"];
	list<string> production_inner_material_U <- ["kg plastic"];
	list<string> production_emissions_U <- ["gCO2e emissions"];
	
	map<string, int> time_cost_U <- [ 
		"modular house"::			4,
		"modular house extension"::	4, 
		"wooden house"::			11, 
		"plastic factory"::			48, 
		"leisure"::					4, 
		"school"::					12, 
		"company"::					3
		];

	/* Production data */
	// TODO : adapter les production et le cout de celle ci sur les bonnes
	map<string, map<string, float>> production_output_inputs_U <- [
		"modular house"::			["m3_wood"::0.0, "kg plastic"::129100.0, "m² land"::70.0, "kWh energy"::500.0], 
		"modular house extension"::	["m3_wood"::0.0, "kg plastic"::38323.0, "m² land"::14.0, "kWh energy"::100.0], 
		"wooden house"::			["m3_wood"::624.0, "kg plastic"::0.0, "m² land"::280.0, "kWh energy"::1000.0], 
		"plastic factory"::			["m3_wood"::184000.0, "kg plastic"::0.0, "m² land"::1000000.0, "kWh energy"::2000.0],
		"leisure"::					["m3_wood"::1807.0, "kg plastic"::451902.0, "m² land"::1200, "kWh energy"::2000.0],
		"school"::					["kg plastic"::0.0, "m3_wood"::10000.0, "m² land"::5000.0, "kWh energy"::2000.0], 
		"company"::					["kg plastic"::0.0, "m3_wood"::10000.0, "m² land"::500.0, "kWh energy"::2000.0],
		"kg_plastic"::				["kg_cotton"::16.5, "kWh energy"::6.0]
	];
	
	map<string, map<string, float>> production_output_emissions_U <- [
		"modular house"::		["gCO2e emissions"::1000000.0], 
		"modular house extension"::	["gCO2e emissions"::3000], 
		"wooden house"::			["gCO2e emissions"::300000.0], 
		"plastic factory"::			["gCO2e emissions"::50000000.0], 
		"leisure"::			["gCO2e emissions"::10000.0], 
		"kg plastic"::				["gCO2e emissions"::0.0], 
		"school"::					["gCO2e emissions"::128000000.0], 
		"company"::					["gCO2e emissions"::128000000.0]
	]; //temporary value for school and company

	/* Counters & Stats */
	map<string, float> tick_production_U <- [];
	map<string, float> tick_consumption_U <- [];
	map<string, float> tick_resources_used_U <- [];
	map<string, float> tick_emissions_U <- [];
	
	
	list<map<string, float>> production_history_U <- [];
	
	mini_city_demography mini_city_ex;

	init { // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0) {
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}

	}

}

species urbanplanning parent: bloc {
	string name <- "urbanplanning";
	urban_producer producer <- nil;
	urban_consumer consumer <- nil;
	map<string, int> to_build <- [];
	//float plastic_budget <- factory_production_capacity * supplies_U["plastic_factory"];
	list<mini_city> mini_cities <- [];

	action setup {
		list<urban_producer> producers <- [];
		list<urban_consumer> consumers <- [];
		
		int total_mini_cities <- length(mini_cities);
		
		if total_mini_cities < 3 {
			write "ERROR: Not enough mini_cities (" + total_mini_cities + "). Minimum: 3";
			return;
		}
		
		loop c over: mini_cities {do initialize_city_buildings(c);}
		create urban_producer number: 1 returns: producers;
		create urban_consumer number: 1 returns: consumers;
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	action tick (list<human> pop) {
		ask residents {
			myself.mini_cities <- self.mini_cities;
		}

		if (length(mini_cities) < 1){
			write "*** ERROR: List of mini-cities obtained in the tick of an empty urbanplanning: " + mini_cities;
		}
		
		do collect_last_tick_data();
		do population_activity(pop);
		do check_building_queue();
		do calculate_minicities_demand();
		do do_minicities_production();
	}

	production_agent get_producer {
		return producer;
	}

	list<string> get_output_resources_labels {
		return production_outputs_U + production_inner_material_U;
	}

	list<string> get_input_resources_labels {
		return production_inputs_U;
	}

	list<string> get_autoproduction_resources_labels {
		return production_inner_material_U;
	}

	action set_external_producer (string product, bloc bloc_agent) {
	// do nothing
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_consumption_U <- consumer.get_tick_consumption(); // collect consumption behaviors
			tick_resources_used_U <- producer.get_tick_inputs_used(); // collect resources used
			tick_production_U <- producer.get_tick_outputs_produced(); // collect production
			tick_emissions_U <- producer.get_tick_emissions(); // collect emissions
			
			ask urban_consumer { // prepare next tick on consumer side
				do reset_tick_counters;
			}

			ask urban_producer { // prepare next tick on producer side
				do reset_tick_counters;
			}

		}

	}

	action do_minicities_production {
		loop mini_ville over: mini_cities {
			ask urban_producer {
				do produce_city(mini_ville);
			}
		}

	}

	action calculate_minicities_demand {
		loop c over: mini_cities {
			int current_wooden_pop <- int(c.pop * wooden_building_ratio);
			int current_modular_pop <- c.pop - current_wooden_pop;
			c.demand["wooden house"] <- float(ceil(current_wooden_pop / max_capacity["wooden house"]));
			float needed_lobbies <- float(ceil(current_modular_pop / max_capacity["modular house"]));
			c.demand["modular house"] <- needed_lobbies;
			float base_capacity_used <- needed_lobbies * min_modular_capacity;
			c.demand["modular house extension"] <- max([0.0, current_modular_pop - base_capacity_used]);
			c.demand["school"] <- float(ceil(c.go_to_school / max_capacity["school"]));
			c.demand["company"] <- float(ceil(c.go_to_work * company_per_worker / max_capacity["company"]));
			c.demand["plastic factory"] <- float(ceil(c.go_to_work * factory_per_worker / max_capacity["plastic factory"]));
			int nb_free <- int(ceil(c.go_to_work * unemployed_per_worker)) + (c.pop - c.go_to_work - c.go_to_school);
			c.demand["leisure"] <- float(ceil(nb_free / max_capacity["leisure"]));
			loop k over: c.demand.keys {
            	c.shortage[k] <- max(0.0, c.demand[k] - c.building_supply[k]);
			}	
		}
	}

	action check_building_queue {
		loop mc over: mini_cities {
			list<building_project> tmp <- [];
			loop project over: mc.queue {
				project.completion_time <- project.completion_time - 1;
				if (project.completion_time = 0){
					string building_name <- project.building;
					int building_quantity <- int(project.quantity);
					mc.building_supply[building_name] <- mc.building_supply[building_name] + building_quantity;
					mc.tick_production[building_name] <- mc.tick_production[building_name] + building_quantity;
					ask producer{
						self.tick_production[building_name] <- self.tick_production[building_name] + building_quantity;
					}
					if (building_name = "wooden house") {
						create wooden_house number: building_quantity { my_city <- mc; }
					} else if (building_name = "modular house") {
						create modular_house number: building_quantity { my_city <- mc; }
					} else if (building_name = "plastic factory") {
						create factory number: building_quantity { my_city <- mc; }
					} else if (building_name = "company") {
						create company number: building_quantity { my_city <- mc; }
					} else if (building_name = "school") {
						create school number: building_quantity { my_city <- mc; }
					} else if (building_name = "leisure") {
						create leisure number: building_quantity { my_city <- mc; }
					}
					tmp <- tmp + [project];
				} 
			}
			mc.queue <- mc.queue - tmp;
			ask tmp{
				do die;
			}
		}

	}
	
	action population_activity (list<human> pop) {
		ask pop { // execute the consumption behavior of the population
			ask myself.urban_consumer {
				do consume(myself);
			}
		}
		
	}

	/**
	 * We define here the production agent of the urbanplanning bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production will be used in the implementation of 
	 */
	species urban_producer parent: production_agent {
		map<string, bloc> external_producers;
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		map<string, float> tick_demand <- [];

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

		map<string, float> get_tick_demand {
			return tick_demand;
		}

		action reset_tick_counters { // reset impact counters
			loop a over: production_inner_material_U {
				tick_resources_used[a] <- 0.0; // reset resources usage
				tick_production[a] <- 0.0;
			}

			loop u over: production_inputs_U {
				tick_resources_used[u] <- 0.0; // reset resources usage
			}

			loop p over: production_outputs_U {
				tick_production[p] <- 0.0; // reset productions
				tick_demand[p] <- 0.0;
			}

			loop e over: production_emissions_U {
				tick_emissions[e] <- 0.0;
			}

		}

		bool produce_city (mini_city mini_ville) {
			bool ok <- true;
			loop c over: mini_ville.shortage.keys {
				loop u over: production_inputs_U{
					float quantity_needed <- production_output_inputs_U[c][u] * mini_ville.shortage[c];
					quantity_needed <- quantity_needed / time_cost_U[c];
					if (c.available_budgets contains u){
						if(quantity_needed >= c.available_budgets[u]){
							quantity_needed <- quantity_needed - c.available_budgets[u];
							c.available_budgets[u] <- 0.0;
						}
						else{
							quantity_needed <- 0.0;
							c.available_budgets[u] <- c.available_budgets[u] - quantity_needed;
						}
					}
					if (!(production_inner_material_U contains u)) {
						if (external_producers.keys contains u and quantity_needed > 0) { // if there is a known external producer for this product/good
							bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
							if not av {
								ok <- false;
							}
						}
					}
				}
			}
			
			return ok;
		}
		bool produce (map<string, float> demand) {
			return true;
		}

		action set_supplier (string product, bloc bloc_agent) {
			write name + ": external producer " + bloc_agent + " set for " + product;
			external_producers[product] <- bloc_agent;
		}

	}

	/**
	 * We define here the consumption agent of the urbanplanning bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is minimalistic here : we apply a random energy consumption for everyone.
	 */
	species urban_consumer parent: consumption_agent {
		map<string, float> consumed <- [];
		//map<string, float> possession <- [];
		map<string, float> get_tick_consumption {
			return copy(consumed);
		}

		init {
			loop key over: production_outputs_U{
				consumed[key] <- 0.0; 
			}
		}

		action reset_tick_counters { // reset choices counters
			loop key over: production_outputs_U{
				consumed[key] <- 0.0; 
			}
		}

		action consume (human h) {
			if(hazard){
				loop key over: production_outputs_U{
					renew_proba[key] <- 0.0; 
				}
			}
			consumed <- renew_proba;
		}

	}
	
	species house{
		string house_type;
		int age <- 0;
		int lifespan;
		int capacity;
		float proba_renew update: renew_proba[house_type];
		mini_city my_city;
		
		reflex renewal{
			age <- age + 1;
			bool renew <- flip(proba_renew);
			if (age = lifespan or renew) {
				ask my_city{
					building_supply[myself.house_type] <- max([0.0, building_supply[myself.house_type] - 1]);
					loop k over: recycled_ratio.keys{
						available_budget[k] <- available_budget[k] + recycled_ratio[k] * production_output_inputs_U[house_type][k];
					}
				}
				do die;
			}
		}
	}
	
	species modular_house parent: house{
		init{
			house_type <- "modular house";
			lifespan <- modular_lifespan;
			capacity <- min_modular_capacity;
		}
	}
	
	species wooden_house parent: house{
		init{
			house_type <- "wooden house";
			lifespan <- wooden_lifespan;
			capacity <- max_capacity["wooden house"];
		}
	}
	
	species public_building{
		string building_type;
		int age <- 0;	
		int lifespan;
		float proba_renew update: renew_proba[building_type];
		mini_city my_city;
		
		reflex renewal{
			age <- age + 1;
			bool renew <- flip(proba_renew);
			if (age = lifespan or renew) {
				ask my_city{
					building_supply[myself.building_type] <- max([0.0, building_supply[myself.building_type] - 1]);ask my_city{
					loop k over: recycled_ratio.keys{
						available_budget[k] <- available_budget[k] + recycled_ratio[k] * production_output_inputs_U[myself.building_type][k];
					}
				}
				do die;
			}
		}
	}
	
	species factory parent: public_building{
		float plastic_quantity <- factory_productivity;
		init{
			building_type <- "plastic factory";
			lifespan <- wooden_lifespan;
		}
	}
	
	species company parent: public_building{
		init{
			building_type <- "company";
			lifespan <- wooden_lifespan;
		}
	}
	
	species school parent: public_building{
		init{
			building_type <- "school";
			lifespan <- wooden_lifespan;
		}
	}
	
	species leisure parent: public_building{
		init{
			building_type <- "leisure";
			lifespan <- wooden_lifespan;
		}
	}
	
	action initialize_city_buildings(mini_city c){
		//Number of residents for each type of house
		int target_wooden_capacity <- int(c.pop * wooden_building_ratio);
    	int target_modular_capacity <- c.pop - target_wooden_capacity;
    	//Number of initialized houses
    	int nb_wooden <- int(ceil(target_wooden_capacity / max_capacity["wooden house"]));
    	int nb_modular <- int(ceil(target_modular_capacity / min_modular_capacity));
    	//Create houses
    	create wooden_house number: nb_wooden{
    		my_city <- c;
    		age <- rnd(0, lifespan - 1);
    	}
    	create modular_house number: nb_modular{
    		my_city <- c;
    		age <- rnd(0, lifespan - 1);
    	}
    	//Create school
    	int nb_school <- int(ceil(c.go_to_school / max_capacity["school"]));
    	create school number: nb_school{
    		my_city <- c;
    		age <- rnd(0, lifespan - 1);
    	}
    	//Create company
    	int nb_company <- int(ceil(c.go_to_work * company_per_worker / max_capacity["company"]));
    	create company number: nb_company{
    		my_city <- c;
    		age <- rnd(0, lifespan - 1);
    	}
    	//Create factory
    	int nb_factory <- int(ceil(c.go_to_work * factory_per_worker / max_capacity["plastic factory"]));
    	create factory number: nb_factory{
    		my_city <- c;
    		age <- rnd(0, lifespan - 1);
    	}
    	//Create leisure
    	int nb_free <- int(ceil(c.go_to_work * unemployed_per_worker)) + (c.pop - c.go_to_work - c.go_to_school);
    	int nb_leisure <- int(ceil(nb_free / max_capacity["leisure"]));
    	create leisure number: nb_leisure{
    		my_city <- c;
    		age <- rnd(0, lifespan - 1);
    	}
    	//Synchronization
    	c.building_supply["modular house"] <- float(nb_modular);
    	c.building_supply["wooden house"] <- float(nb_wooden);
    	c.building_supply["plastic factory"] <- float(nb_factory);
    	c.building_supply["company"] <- float(nb_company);
    	c.building_supply["school"] <- float(nb_school);
    	c.building_supply["leisure"] <- float(nb_leisure);
	    loop b over: c.production_outputs_inputs_U {
    	    c.potential_building_supply[b] <- c.building_supply[b];
    	}
	}
}

experiment run_urban type: gui {

	reflex {
		loop i over: production_inputs_U {
			save [cycle, i, tick_resources_used_U[i]] to: "results_files/urbanplanning/urban_ressources.csv" rewrite: false;
		}

		loop i over: production_inner_material_U {
			save [cycle, i, tick_resources_used_U[i]] to: "results_files/urbanplanning/urban_plastic_ressources.csv" rewrite: false;
		}

		loop o over: production_outputs_U {
			save [cycle, o, tick_production_U[o]] to: "results_files/urbanplanning/urban_production.csv" rewrite: false;
			save [cycle, o, tick_consumption_U[o]] to: "results_files/urbanplanning/urban_consumption.csv" rewrite: false;
		}

		loop e over: production_emissions_U {
			save [cycle, e, tick_emissions_U[e]] to: "results_files/urbanplanning/urban_emission.csv" rewrite: false;
		}

	}

	output {
		display Urban_information type: 2d {

			chart "Total production" type: series size: {0.5, 0.5} position: {0.5, 0} {
				loop c over: production_outputs_U {
					data c value: tick_production_U[c];
				}
			}

			chart "Resources usage" type: series size: {0.5, 0.5} position: {0, 0.5} {
				loop r over: production_inputs_U {
					data r value: tick_resources_used_U[r];
				}
			}
			
			chart "Consumption trending" type: series size: {0.5, 0.5} position: {0.5, 0}{
				loop c over: production_outputs_U {
					data c value: tick_consumption_U[c];
				}
			}

			chart "Production emissions" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				loop e over: production_emissions_U {
					data e value: tick_emissions_U[e];
				}
			}

		}

		monitor "Mini-ville exemple" value: mini_city_ex.individuals;
	}

}