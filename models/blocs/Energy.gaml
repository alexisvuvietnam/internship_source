/**
* Name: Energy bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Energy

import "../API/API.gaml"

/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global{

	/* Setup */
	list<string> production_inputs_E <- ["L water", "m² land", "m3_wood", "kg_coton"];
	list<string> production_outputs_E <- ["kWh energy"];
	list<string> production_emissions_E <- ["gCO2e emissions"];
	
	/* Production data */
	// Types d'énergie
    list<string> energy_types <- ["nuclear", "hydro", "wind", "solar"];
    // Saisons 
    list<string> saisons <- ["spring", "summer", "autumn", "winter"];
    
    // Structure: energy_type -> resource -> quantité par kWh
    map<string, map<string, float>> production_inputs_per_kWh <- [
        "nuclear"::["L water"::50.0],//, "m² land"::0.001],
        "hydro"::["L water"::100.0],//, "m² land"::0.002],
        "wind"::["L water"::10.0],//, "m² land"::0.005],
        "solar"::["L water"::5.0]//, "m² land"::0.010]
    ];
    
    // Structure: energy_type -> émissions par kWh
    map<string, float> emissions_per_kWh <- [
        "nuclear"::10.0,
        "hydro"::5.0,
        "wind"::2.0,
        "solar"::1.0
    ];
	//  1m3_wood = 700kg_bois
	map<string, map<string, float>> factory_construction_cost<- [
		//"kg cotton"::["nuclear"::150000.0,"wind"::300.0,"hydro"::200000.0,"solar"::10.0],
		//"kg_wood"::["nuclear"::300000.0,"wind"::200.0,"hydro"::500000.0,"solar"::50.0],
		"m3_wood"::["nuclear"::428.571,"wind"::0.285,"hydro"::714.285,"solar"::0.0714],
		"m² land"::["nuclear"::2500000.0,"wind"::4000.0,"hydro"::2000.0,"solar"::1.8]];
		
	map<string,float> stock <- ["kg cotton":: 1500000.0, "kg wood":: 300000.0, "m² land":: 1500000000000.0];
		
	/*tot     | 6260 | 312 | 4333| 135
	printemps | 1565 | 118 | 990 | 35
	été       | 1565 | 56  | 540 | 65
	automne   |1565  | 87  | 1260| 25 
	hiver     |1565  | 50  | 1710| 10  */
	//production totale par m2
	map<string,map<string, float>> factory_production<- 
		["spring"::["nuclear"::521.7, "hydro"::39.3, "wind"::330.0, "solar"::11.7],
		"summer"::["nuclear"::521.7, "hydro"::18.7, "wind"::180.0, "solar"::21.7],
		"autumn"::["nuclear"::521.7, "hydro"::29.0, "wind"::420.0, "solar"::8.3],
		"winter"::["nuclear"::521.7, "hydro"::16.7, "wind"::570.0, "solar"::3.3]
	];
	map<string,float> total_factory_production <-["nuclear"::6260.0, "hydro"::311.0, "wind"::4500.0, "solar"::135.0];

    
    //(N,1-4km2)(E,2 500-5 000m2)(S,1.7-2m2)(H,2000m2)
	
	map<string, map<string, float>> factory_ressource<- [
        "m² land"::["nuclear"::5000000.0,"wind"::4000.0,"hydro"::500000.0,"solar"::1.8],
        "L water"::["nuclear"::2500000.0,"wind"::10000,"hydro"::10000000.0,"solar"::100000.0]
    ];
    
	list<string> energys<- ["nuclear", "hydro", "wind", "solar"];
		
	/* Consumption data */
	map<string, int> min_kWh_conso <- ["spring":: 200, "summer"::270, "autumn"::200, "winter"::300]; // Note : this is real data
	map<string,int> max_kWh_conso <- ["spring":: 200, "summer"::320, "autumn"::250, "winter"::400]; // Note : this is real data 
	
	/* Counters & Stats */
	map<string, float> tick_production_E <- [];
	map<string, float> tick_pop_consumption_E <- [];
	map<string, float> tick_resources_used_E <- [];
	map<string, float> tick_emissions_E <- [];
	map<string, float> tick_stock_E <- [];
	
	//macro
	 map<string, float> mix_E <- ["nuclear"::0.40, "wind"::0.25, "hydro"::0.20, "solar"::0.15];
	float terres_utilise <-4000000000.0; //4 0000km2 en m2
	
	
	float land_total_E <- [];
	
	//Is it used ?
	string build_energy_type <- "solar";
    int build_quantity <- 1;
    
	
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
 * This bloc is very minimalistic : it only apply an average consumption for the population, and provide energy to other blocs.
 */
species energy parent:bloc{
	string name <- "energy";
	
	energy_producer producer <- nil;
	energy_consumer consumer <- nil;
	
	map<string, float> n_factory<- [];
	map<string, float> t0_n_factory<- [];
	float land_total<- terres_utilise;
	
	map<string, float> stock_E<- [];
	
	action setup{
		list<energy_producer> producers <- [];
		list<energy_consumer> consumers <- [];
		create energy_producer number:1 returns:producers; // instanciate the agricultural production handler
		create energy_consumer number:1 returns:consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
		
		//Calcul réppartition terres par rapport mix_E
		float s <- 0.0;
		float e <- 0.0;
		map<string,float> land_by_type <- [];
		loop energy_type over: energy_types {
			s <- s + mix_E[energy_type]/total_factory_production[energy_type];
        }
        e <- land_total/s;
        loop energy_type over: energy_types {
			land_by_type[energy_type] <- (mix_E[energy_type]*e)/total_factory_production[energy_type];
			write " energie "+ energy_type + " = "+ land_by_type[energy_type];
        }
		
		
		stock_E["kWh energy"]<- 1.0; //10 000 000 000.0
		
		t0_n_factory["nuclear"]<- 5;
		t0_n_factory["hydro"]<- 10;
		t0_n_factory["wind"]<- 100;
		t0_n_factory["solar"]<- 10000;
		
		n_factory["nuclear"]<- land_by_type["nuclear"]/factory_ressource["m² land"]["nuclear"];
		n_factory["hydro"]<- land_by_type["hydro"]/factory_ressource["m² land"]["hydro"];
		n_factory["wind"]<- land_by_type["wind"]/factory_ressource["m² land"]["wind"];
		n_factory["solar"]<- land_by_type["solar"]/factory_ressource["m² land"]["solar"];
		write " n : " + n_factory["nuclear"] + " h : " + n_factory["hydro"] + " w : " + n_factory["wind"] + " s : " + n_factory["solar"];
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
//	float get_land_total{
//		return land_total;
//	}
	
	map<string, float> get_stock_E{
		return stock_E;
	}
	
	
	production_agent get_producer{
		write "producer inside target bloc : "+producer;
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_E;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_E;
	}
	
	action set_stock_E(float stock){
		stock_E["kWh energy"] <- stock;
	}
	
	map<string, float> get_n_factory {
        return copy(n_factory);
    }
    
    map<string, float> get_production_by_type {
        map<string, float> production <- [];
        string saison;
       	int saison_index <- cycle mod 12;
			if(saison_index < 3){saison <- "spring";}
			else if(saison_index < 6){saison <- "summer";}
			else if(saison_index < 9){saison <- "autumn";}
			else if(saison_index < 12){saison <- "winter";}
        loop energy_type over: energy_types {
            production[energy_type] <- n_factory[energy_type] * factory_production[saison][energy_type] * factory_ressource["m² land"][energy_type];
        }
        return production;
    }
    
    map<string, float> get_pollution_by_type {
        map<string, float> pollution <- [];
		string saison;
       	int saison_index <- cycle mod 12;
			if(saison_index < 3){saison <- "spring";}
			else if(saison_index <6){saison <- "summer";}
			else if(saison_index < 9){saison <- "autumn";}
			else if(saison_index < 12){saison <- "winter";}
        loop energy_type over: energy_types {
            pollution[energy_type] <- n_factory[energy_type] * factory_production[saison][energy_type] * factory_ressource["m² land"][energy_type] * emissions_per_kWh[energy_type];
        }
        return pollution;
    }
    
    //A MODIFIER loop over input
    map<string,map<string, float>> get_ressource_by_type {
    	//factory_ressource
        map<string,map<string, float>> resources <- [];
        // Initialiser les sous-maps
   	 	resources["L water"] <- map<string, float>([]);
    	resources["m² land"] <- map<string, float>([]);
    	
		string saison;
       	int saison_index <- cycle mod 12;
			if(saison_index < 3){saison <- "spring";}
			else if(saison_index <6){saison <- "summer";}
			else if(saison_index < 9){saison <- "autumn";}
			else if(saison_index < 12){saison <- "winter";}
        loop energy_type over: energy_types {
            resources["L water"][energy_type] <- n_factory[energy_type] * factory_production[saison][energy_type]* factory_ressource["L water"][energy_type];
            resources["m² land"][energy_type] <- n_factory[energy_type] * factory_production[saison][energy_type]* factory_ressource["m² land"][energy_type];
        }
        write " ressources = "+ resources;
        return resources;
    }

	
	action set_external_producer(string product, bloc bloc_agent){
		ask producer{
			do set_supplier(product, bloc_agent);
		}
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_E <- consumer.get_tick_consumption(); // collect consumption behaviors
    		tick_resources_used_E <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_E <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_E <- producer.get_tick_emissions(); // collect emissions
	    	
	    	//land_total <- get_land_total();
	    	stock_E <- get_stock_E();
    	
	    	ask energy_consumer{ // prepare next tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask energy_producer{ // prepare next tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{ // execute the consumption behavior of the population
    		ask energy_consumer{ // utiliser directement energy_consumer
    			do consume(myself); // individuals consume agricultural goods
    		}
    	}
    	 
    	ask energy_consumer{ // produce the resuired quantities
    		ask energy_producer{
    			do stock_update();
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]);
		    	}
		    } 
    	}
    }
    //CONSTRUIRE PLUS !
    action build_infrastructure(string energy_type, int quantity) {
	    // Vérifier les ressources nécessaires
	    map<string, float> total_cost <- (map<string, float>([]));
	    
	    loop material over: factory_construction_cost.keys {
	        total_cost[material] <- factory_construction_cost[material][energy_type] * quantity;
	        
	        // Vérifier si on a assez de ressources
	        // (Vous devrez ajouter un stock de ressources à votre espèce energy)
	        if (stock[material] < total_cost[material]) {
	            write "Pas assez de " + material + " pour construire " + quantity + " " + energy_type + " usines";
	            return;
	        }
	    }
	    
	    // Déduire les ressources
	    loop material over: total_cost.keys {
	        stock[material] <- stock[material] - total_cost[material];
	    }
	    
	    // Ajouter les usines
	    n_factory[energy_type] <- n_factory[energy_type] + quantity;
	    
	    write " "+quantity + " nouvelle(s) usine(s) " + energy_type + " construite(s) !";
	}
}

	/**
	 * We define here the production agent of the energy bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is minimalistic here : we apply an average resource consumption and emissions for the energy production.
	 */
	species energy_producer parent:production_agent{
		map<string, float> tick_resources_used <- (map<string, float>([]));
		map<string, float> tick_production <- (map<string, float>([]));
		map<string, float> tick_emissions <- (map<string, float>([]));
		
		map<string, bloc> ext_producers <- [];
		
		//GETTER
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
		
		//SETTER
		action set_tick_resources_used(map<string, float> new_resources) {
			tick_resources_used["m² land"] <- new_resources["m² land"];
			tick_resources_used["L water"] <- new_resources["L water"];
	    }
	    action set_tick_production(map<string, float> new_resources) {
	        tick_production <- new_resources;
	    }
	    action set_tick_emissions(map<string, float> new_resources) {
	        tick_emissions <- new_resources;
	    }
	
		//RESET
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_E{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_E{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_E{
				tick_emissions[e] <- 0.0;
			}
		}
		
		//PRODUCE
		bool produce(map<string,float> demand){ // apply the input
		
			bool ok <- true;
			loop energy_type over: demand.keys{
				ask energy{
					if(demand[energy_type] > stock_E[energy_type]){
						ok <- false;
					}
				}
			}
			
			if(ok){
				loop energy_type over: demand.keys {
					ask energy {
						stock_E[energy_type] <- stock_E[energy_type] - demand[energy_type];
					}
				}
			}
			return ok;		        
		}
		
		action stock_update{ // rajoute de l'energie a notre stock en récuperant l'eau des autres
			
			
			map<string, float> prod <- (map<string, float>([]));
		    map<string, float> poll <- (map<string, float>([]));
			ask energy {
					// Energie
					
					//stock a zero pour debut de tick
					stock_E["kWh energy"] <- 0.0;
					
		            map<string, float> production_by_type <- get_production_by_type();
		            map<string, float> pollution_by_type <- get_pollution_by_type();

		            loop energy_type over: energy_types {
		                prod[energy_type] <- production_by_type[energy_type];
		                poll[energy_type] <- pollution_by_type[energy_type];
		            }
		            
		            //le total en kWh
		            float total_kWh <- 0.0;
		            float total_pollution <- 0.0;
		            loop energy_type over: energy_types {
		                total_kWh <- total_kWh + production_by_type[energy_type];
		                total_pollution <- total_pollution + pollution_by_type[energy_type];
		            }
		            prod["kWh energy"] <- total_kWh; //total energies
		            poll["Total"] <- total_pollution;

		        }
		        
		    map<string, float> ress <- ["L water"::0.0, "m² land"::0.0];
		    ask energy{
		    	map<string, float> all_factory <- get_n_factory();
			    loop energy_type over: energy_types {
	                        //ress["L water"] <- ress["L water"] + (all_factory[energy_type] * factory_ressource["L water"][energy_type]);
	                        ress["m² land"] <- ress["m² land"] + (all_factory[energy_type] * factory_ressource["m² land"][energy_type]);
	            }
		    }
		        
		 	float total_water;
		 	loop energy_type over: energy_types {
		 		total_water <- total_water + production_inputs_per_kWh[energy_type]["L water"] * prod[energy_type];
		 	}
		 
		 	bool av <- ext_producers["L water"].producer.produce(["L water"::total_water]);
		 	if(av){
		 		ask energy{
		 			stock_E["kWh energy"] <- stock_E["kWh energy"] + prod["kWh energy"];
		 		}
		 		
		 		//write "tick prod"+tick_production["kWh energy"];
		 		tick_production["kWh energy"] <- tick_production["kWh energy"] + prod["kWh energy"];
		 		//write "tick prod"+tick_production["kWh energy"];
		 		tick_resources_used["L water"] <- tick_resources_used["L water"] + total_water;
		 		ress["L water"] <- ress["L water"] + total_water;
		 		tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + poll["Total"];
		 		
		 		do set_tick_production(prod);
		 		do set_tick_resources_used(ress);
		 		//write "prod"+prod;
		   		do set_tick_emissions(poll);
		   		
		 		
		 		// write "E - Production succeed."+ tick_production["kWh energy"];
		 	}else{
		 		write "E - Production failed.";
		 	}
		}
		
		//SUPPLY
		action set_supplier(string product, bloc bloc_agent){
			write name+" demande "+product+" à "+bloc_agent;
			ext_producers[product] <- bloc_agent;
		}
	
	}
	
	/**
	 * We define here the conumption agent of the energy bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is minimalistic here : we apply a random energy consumption for everyone.
	 */
	species energy_consumer parent:consumption_agent{
	
		map<string, float> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_E{
				consumed[c] <- 0;
			}
		}
		
		action reset_tick_counters{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){
			string saison;
       	int saison_index <- cycle mod 12;
			if(saison_index < 3){saison <- "spring";}
			else if(saison_index <6){saison <- "summer";}
			else if(saison_index < 9){saison <- "autumn";}
			else if(saison_index < 12){saison <- "winter";}
		    string choice <- one_of(production_outputs_E); // note : here, there is only one production, energy
			consumed[choice] <- consumed[choice]+rnd(min_kWh_conso[saison], max_kWh_conso[saison]); // monthly consume a random amount of energy 
		}
	}


/**
 * We define here the experiment and the displays related to energy. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_energy type: gui {

    
    output {
		display Energy_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_E{
			    	data c value: tick_pop_consumption_E[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Production par type d'énergie (kWh)" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    data "Nucléaire" value: tick_production_E["nuclear"] color: #red;
			    data "Hydroélectrique" value: tick_production_E["hydro"] color: #blue;
			    data "Éolien" value: tick_production_E["wind"] color: #green;
			    data "Solaire" value: tick_production_E["solar"] color: #yellow;
			    
			    data "Total" value: tick_production_E["kWh energy"] color: #black;
			}
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5} {
				data "m² land" value: tick_resources_used_E["m² land"] color: #green;
				data "L water" value: tick_resources_used_E["L water"] color: #blue;
			    loop r over: production_inputs_E{
			    	data r value: tick_resources_used_E[r];
			    }
			    
			}
			chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    data "Nucléaire" value: tick_emissions_E["nuclear"] color: #red;
			    data "Hydroélectrique" value: tick_emissions_E["hydro"] color: #blue;
			    data "Éolien" value: tick_emissions_E["wind"] color: #green;
			    data "Solaire" value: tick_emissions_E["solar"] color: #yellow;
			    
			    data "Total" value: tick_emissions_E["Total"] color: #black;
			}
	    }
	}
}
