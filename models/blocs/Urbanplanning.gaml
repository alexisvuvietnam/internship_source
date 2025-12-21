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
	list<string> production_inputs_U <- ["m3_wood", "Wh energy", "kg_coton", "m² land"];
	list<string> production_outputs_U <- ["modular_house_lobby", "modular_house_extension", "wooden_building"];
	list<string> autoproduction_U <- ["kg_plastic"];
	list<string> production_emissions_U <- ["gCO2e emissions"];

	/* Production data */
	// TODO : adapter les production et le cout de celle ci sur les bonnes
	map<string, map<string, float>>
	production_output_inputs_U <- ["modular_house_lobby"::["m3_wood"::0.0, "kg_plastic"::3000.0], "modular_house_extension"::["m3_wood"::0.0, "kg_plastic"::600.0], "wooden_building"::["m3_wood"::80.0, "kg_plastic"::0.0], "plastic_factory"::["m3_wood"::184000.0, "kg_plastic"::42000000.0], "kg_plastic"::["kg_coton"::16.5, "Wh energy"::6.0]];
	map<string, map<string, float>>
	production_output_emissions_U <- ["modular_house_lobby"::["gCO2e emissions"::1000000.0], "modular_house_extension"::["gCO2e emissions"::30000.0], "wooden_building"::["gCO2e emissions"::300000.0], "plastic_factory"::["gCO2e emissions"::50000000.0], "kg_plastic"::["gCO2e emissions"::0.0]];
	map<string, map<string, float>>
	supply_upkeep_U <- ["modular_house_lobby"::["m² land"::0.0], "modular_house_extension"::["m² land"::50.0], "wooden_building"::["m² land"::100.0], "plastic_factory"::["m² land"::1000000.0]];
	float factory_production_capacity <- 11000000.0;
	map<string, float> indivudual_consumption_U <- ["modular_house_extension"::1.0, "modular_house_lobby"::0.05, "wooden_building"::0.000175];
	map<string, float> supplies_U <- ["modular_house_extension"::70000000.0, "modular_house_lobby"::3500000.0, "wooden_building"::1400.0, "plastic_factory"::10.0];
	map<string, int> time_cost_U <- ["modular_house_extension"::1, "modular_house_lobby"::3, "wooden_building"::6, "plastic_factory"::48];

	/* Counters & Stats */
	map<string, float> tick_production_U <- [];
	map<string, float> tick_pop_consumption_U <- [];
	map<string, float> tick_resources_used_U <- [];
	map<string, float> tick_emissions_U <- [];
	list<map<string, float>> production_history_U <- [];

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
 */
species urbanplanning parent: bloc {
	string name <- "urbanplanning";
	urban_producer producer <- nil;
	urban_consumer consumer <- nil;
	map<string, int> to_build <- [];
	float plastic_budget <- factory_production_capacity * supplies_U["plastic_factory"];

	action setup {
		list<urban_producer> producers <- [];
		list<urban_consumer> consumers <- [];
		create urban_producer number: 1 returns: producers;
		create urban_consumer number: 1 returns: consumers;
		producer <- first(producers);
		consumer <- first(consumers);
	}

	action tick (list<human> pop) {
		do collect_last_tick_data();
		do population_activity(pop);
	}

	production_agent get_producer {
		return producer;
	}

	list<string> get_output_resources_labels {
		return production_outputs_U + autoproduction_U;
	}

	list<string> get_input_resources_labels {
		return production_inputs_U;
	}

	list<string> get_autoproduction_resources_labels {
		return autoproduction_U;
	}

	action set_external_producer (string product, bloc bloc_agent) {
	// do nothing
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_pop_consumption_U <- consumer.get_tick_consumption(); // collect consumption behaviors
			tick_resources_used_U <- producer.get_tick_inputs_used(); // collect resources used
			tick_production_U <- producer.get_tick_outputs_produced(); // collect production
			tick_emissions_U <- producer.get_tick_emissions(); // collect emissions

			//loop c over: production_outputs_U{
			//    production_history_U[c] <- production_history_U[c] + [tick_production_U[c]];
			//}
			ask urban_consumer { // prepare next tick on consumer side
				do reset_tick_counters;
			}

			ask urban_producer { // prepare next tick on producer side
				do reset_tick_counters;
			}

		}

	}

	action population_activity (list<human> pop) {
		ask pop { // execute the consumption behavior of the population
			ask myself.urban_consumer {
				do consume(myself);
			}

		}

		plastic_budget <- factory_production_capacity * supplies_U["plastic_factory"];
		ask urban_consumer { // produce the resuired quantities
			ask urban_producer {
			// Battiments non-individuels
				loop p over: to_build.keys {
					do produce([p::to_build[p]]);
				}

				if (plastic_budget < 0) {
					plastic_budget <- 0.0;
				}

				to_build <- ["plastic_factory"::0];

				// Battiments indiviuels
				loop c over: myself.consumed.keys {
					do produce([c::myself.consumed[c]]);
				}
				//do produce(["plastic_factory"::100]);
				add get_tick_demand() to: production_history_U;
				//production_history_U <- production_history_U + get_tick_demand();
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
			loop a over: autoproduction_U {
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

		bool produce (map<string, float> demand) { // apply the input
			bool ok <- true;
			list<map<string, float>> valeurs <- [];

			//write "Urban produce : " + demand;
			loop c over: demand.keys {
				demand[c] <- demand[c] - supplies_U[c];
				if (demand[c] < 0) {
					demand[c] <- 0;
				}

				loop u over: production_inputs_U { // needs (resources consumed/emitted) for this demand
					float quantity_needed <- production_output_inputs_U[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand

					// Gestion cout d'entretient
					if (supply_upkeep_U.keys contains c) {
						map<string, float> upkeep_requirements <- supply_upkeep_U[c];
						if (upkeep_requirements.keys contains u) {
							float upkeep_cost <- supplies_U[c] * upkeep_requirements[u];
							quantity_needed <- quantity_needed + upkeep_cost;
						}

					}

					tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
					if (!(autoproduction_U contains u)) {
						if (external_producers.keys contains u and quantity_needed > 0) { // if there is a known external producer for this product/good
							bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
							if not av {
								ok <- false;
							}

						}

					}

				}

				loop a over: autoproduction_U {
					float quantity_needed <- production_output_inputs_U[c][a] * demand[c]; // quantify the resources consumed/emitted by this demand

					// Pénuries plastique
					if (plastic_budget <= 0) { // Pas de budget
						quantity_needed <- 0.0;
						demand[c] <- 0;
						plastic_budget <- plastic_budget - quantity_needed;
					} else if (quantity_needed > plastic_budget) { // Overbudget
						float production_cost <- production_output_inputs_U[c][a];
						demand[c] <- plastic_budget / production_cost;
						plastic_budget <- plastic_budget - quantity_needed;
						quantity_needed <- production_cost * demand[c];
					} else {
						plastic_budget <- plastic_budget - quantity_needed;
					}

					tick_production[a] <- tick_production[a] + quantity_needed;
					tick_resources_used[a] <- tick_resources_used[a] + quantity_needed;
					loop u over: production_output_inputs_U[a].keys {
						tick_resources_used[u] <- tick_resources_used[u] + production_output_inputs_U[a][u] * quantity_needed;
					}

				}

				loop e over: production_emissions_U { // apply emissions
				//write "Emissions : "+e + " Product : "+c;
				//write "Quantity emmited : "+production_output_emissions_U[c];
					float quantity_emitted <- production_output_emissions_U[c][e] * demand[c];
					tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
				}

				tick_production[c] <- tick_production[c] + demand[c];
				supplies_U[c] <- supplies_U[c] + tick_production[c];
				tick_demand[c] <- tick_demand[c] + (demand[c] + supplies_U[c]);

				// Code obsolète pour le temps de production macro
				//if(length(production_history_U) >= time_cost_U[c] and c != "kg_plastic"){
				//	float to_build <- (production_history_U at (length(production_history_U) - time_cost_U[c]))[c];
				//	//write c + " demand : " + demand[c] + " supplies : " + supplies_U[c] + " to_build :"+to_build;
				//	if(to_build > supplies_U[c]){
				//		supplies_U[c] <- to_build;
				//	}
				//}

			}

			// Gestion spécifique du plastique
			float production_capacity <- factory_production_capacity * supplies_U["plastic_factory"];
			float quantity_supplied <- min(production_capacity, tick_production["kg_plastic"]);
			if (plastic_budget <= 0) {
				int nb_to_build <- int(ceil(abs(plastic_budget) / factory_production_capacity));
				if (to_build["plastic_factory"] <= supplies_U["plastic_factory"]) {
					to_build["plastic_factory"] <- nb_to_build + supplies_U["plastic_factory"];
				}

			}

			tick_production["kg_plastic"] <- quantity_supplied;
			float quantity_usedup <- min(production_capacity, tick_resources_used["kg_plastic"]);
			tick_resources_used["kg_plastic"] <- quantity_usedup;

			//add tick_production to: production_history_U;
			return ok;
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
		map<string, float> possession <- [];
		map<string, float> get_tick_consumption {
			return copy(consumed);
		}

		init {
			loop c over: production_outputs_U {
				consumed[c] <- 0;
				possession[c] <- 0;
			}

		}

		action reset_tick_counters { // reset choices counters
			loop c over: consumed.keys {
				consumed[c] <- 0;
			}

		}

		action consume (human h) {
			loop c over: indivudual_consumption_U.keys {
				consumed[c] <- consumed[c] + (indivudual_consumption_U[c] * 7000); // Chaque habitant en représente 7000
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

	reflex {
		loop i over: production_inputs_U {
		/*if(not(i = "kg_coton")){
				save [cycle, i, tick_resources_used_U[i]] to: "results_files/urbanplanning/urban_ressources.csv" rewrite: false;
			}*/
			save [cycle, i, tick_resources_used_U[i]] to: "results_files/urbanplanning/urban_ressources.csv" rewrite: false;
		}

		loop i over: autoproduction_U {
			save [cycle, i, tick_resources_used_U[i]] to: "results_files/urbanplanning/urban_ressources.csv" rewrite: false;
		}

		loop o over: production_outputs_U {
			save [cycle, o, tick_production_U[o]] to: "results_files/urbanplanning/urban_production.csv" rewrite: false;
		}

		loop o over: production_outputs_U {
			save [cycle, o, tick_pop_consumption_U[o]] to: "results_files/urbanplanning/urban_consumption.csv" rewrite: false;
		}

		loop e over: production_emissions_U {
			save [cycle, e, tick_emissions_U[e]] to: "results_files/urbanplanning/urban_emission.csv" rewrite: false;
		}

	}

	output {
		display Urban_information {
			chart "Population direct consumption" type: series size: {0.5, 0.5} position: {0, 0} {
				loop c over: production_outputs_U {
					data c value: tick_pop_consumption_U[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
				}

			}

			chart "Total production" type: series size: {0.5, 0.5} position: {0.5, 0} {
				loop c over: production_outputs_U {
					data c value: tick_production_U[c];
				}
				//loop a over: autoproduction_U{
				//data a value: tick_production_U[a];
				//}
			}

			chart "Resources usage" type: series size: {0.5, 0.5} position: {0, 0.5} {
				loop r over: production_inputs_U {
					data r value: tick_resources_used_U[r];
				}
				//loop a over: autoproduction_U{
				//data a value: tick_resources_used_U[a];
				//}
			}

			chart "Production emissions" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				loop e over: production_emissions_U {
					data e value: tick_emissions_U[e];
				}

			}

		}

	}

}