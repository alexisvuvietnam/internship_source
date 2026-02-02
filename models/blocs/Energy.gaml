/**
* Name: Energy bloc (MOSIMA) - Version Micro avec Mix Énergétique
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Energy

import "../API/API.gaml"

global{
	/* Setup */
	list<string> production_inputs_E <- ["L water", "m² land", "m3_wood", "kg_cotton"];
	list<string> production_outputs_E <- ["kWh energy"];
	list<string> production_emissions_E <- ["gCO2e emissions"];
	
	/* Production data */
	list<string> energy_types <- ["nuclear", "hydro", "wind", "solar"];
    list<string> saisons <- ["spring", "summer", "autumn", "winter"];
    
	//Production totale annuelle par infrastructure (kWh)
	map<string, float> total_factory_production <- ["nuclear"::32909000000.0, "hydro"::288000000.0, "wind"::157000000.0, "solar"::230000000.0];
	
    map<string, map<string,float>> factory_season_factor <- [
    	"nuclear"::["spring"::0.25, "summer"::0.25, "autumn"::0.25, "winter"::0.25], 
		"hydro"::["spring"::0.38, "summer"::0.18, "autumn"::0.28, "winter"::0.16], 
		"wind"::["spring"::0.22, "summer"::0.12, "autumn"::0.27, "winter"::0.39], 
		"solar"::["spring"::0.26, "summer"::0.48, "autumn"::0.18, "winter"::0.08]
	];
    
    // Production par infrastructures et par tick (kWh)
    map<string, map<string, float>> factory_production <- [
    	"spring"::[
			"nuclear"::(total_factory_production["nuclear"]*factory_season_factor["nuclear"]["spring"])/3,
			"hydro"::(total_factory_production["hydro"]*factory_season_factor["hydro"]["spring"])/3,
			"wind"::(total_factory_production["wind"]*factory_season_factor["wind"]["spring"])/3, 
			"solar"::(total_factory_production["solar"]*factory_season_factor["solar"]["spring"])/3],
					
		"summer"::[
			"nuclear"::(total_factory_production["nuclear"]*factory_season_factor["nuclear"]["summer"])/3,
		   	"hydro"::(total_factory_production["hydro"]*factory_season_factor["hydro"]["summer"])/3,
		   	"wind"::(total_factory_production["wind"]*factory_season_factor["wind"]["summer"])/3, 
		   	"solar"::(total_factory_production["solar"]*factory_season_factor["solar"]["summer"])/3],
		   	
		"autumn"::[
			"nuclear"::(total_factory_production["nuclear"]*factory_season_factor["nuclear"]["autumn"])/3,
		   	"hydro"::(total_factory_production["hydro"]*factory_season_factor["hydro"]["autumn"])/3,
		   	"wind"::(total_factory_production["wind"]*factory_season_factor["wind"]["autumn"])/3,
		    "solar"::(total_factory_production["solar"]*factory_season_factor["solar"]["autumn"])/3],
		    
		"winter"::[
			"nuclear"::(total_factory_production["nuclear"]*factory_season_factor["nuclear"]["winter"])/3,
		   	"hydro"::(total_factory_production["hydro"]*factory_season_factor["hydro"]["winter"])/3,
		   	"wind"::(total_factory_production["wind"]*factory_season_factor["wind"]["winter"])/3,
		    "solar"::(total_factory_production["solar"]*factory_season_factor["solar"]["winter"])/3]
	];
    
    //Ressources par infrastructures et par tick
	map<string, map<string, float>> factory_ressource <- [
	    "m² land":: ["nuclear"::1500000.0, "wind"::500.0, "hydro"::2000000.0, "solar"::20000.0],
	    "L water":: ["nuclear"::800000.0, "wind"::50.0, "hydro"::5000000.0, "solar"::100.0]
	];
    
    //Émissions par kWh (gCO2e)
    map<string, float> emissions_per_kWh <- [
        "nuclear"::4.0,
        "hydro"::6.0,
        "wind"::15.0,
        "solar"::34.0
    ];
    
	// Coût de construction (ressources nécessaires par infrastructure)
	map<string, map<string, float>> factory_construction_cost <- [
	    "m3_wood":: ["nuclear"::12000.0, "wind"::45.0, "hydro"::8500.0, "solar"::5.0],
	    "kg_cotton"::["nuclear"::500000.0, "wind"::1200.0, "hydro"::350000.0, "solar"::150.0],
	    "m² land":: ["nuclear"::1500000.0, "wind"::500.0, "hydro"::2000000.0, "solar"::20000.0]
	];
	
	map<string, float> duree_de_vie <- ["nuclear"::600.0, "hydro"::1080.0, "wind"::240.0, "solar"::300.0];
	
	// Parc initial
	map<string, float> park_FR <- ["nuclear"::11, "hydro"::230, "wind"::300, "solar"::130];
	//map<string, float> park_FR <- ["nuclear"::1, "hydro"::3, "wind"::1, "solar"::1];
	
	/* Consumption data */
	map<string, int> min_kWh_conso <- ["spring"::200, "summer"::270, "autumn"::200, "winter"::300];
	map<string, int> max_kWh_conso <- ["spring"::200, "summer"::320, "autumn"::250, "winter"::400];
	
	/* Counters & Stats */
	map<string, float> tick_production_E <- map<string, float>([]);
	map<string, float> tick_pop_consumption_E <- map<string, float>([]);
	map<string, float> tick_resources_used_E <- map<string, float>([]);
	map<string, float> tick_emissions_E <- map<string, float>([]);
	map<string, float> tick_stock_E <- ["kWh energy"::100000000000.0];
	float tick_external_demand_E <- 0.0;
	float surplus <- 0.0;
	float marge <- 30.0;
	float tick_consommee <- 0.0;
	int age_tick;
	
	// Mix énergétique cible
	map<string, float> mix_E <- ["nuclear"::0.40, "wind"::0.25, "hydro"::0.20, "solar"::0.15];
	
	init{
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
		}
	}
}

//INFRASTRUCTURES

species infrastructure {
    string type;
    float age <- 0.0;
    float max_age;
    float monthly_production <- 0.0;
    float water_consumption <- 0.0;
    float land_usage <- 0.0;
    float emission_factor <- 0.0;
    bool operational <- true;
    rgb color <- #gray;
    
    reflex aging {
        age <- age + 1.0;
        if (age > max_age) {
            operational <- false;
            do die;
        }
    }
    
    float get_current_production {
        if (!operational) {return 0.0;}
        string saison <- current_season();
        return factory_production[saison][type];
    }
    
    float get_current_emissions {
        if (!operational) {return 0.0;}
        return get_current_production() * emission_factor;
    }
    
    string current_season {
        int saison_index <- cycle mod 12;
        if(saison_index < 3) {return "spring";}
        else if(saison_index < 6) {return "summer";}
        else if(saison_index < 9) {return "autumn";}
        else {return "winter";}
    }
    
    aspect base {
        draw circle(10000) color: operational ? color : #darkgray;
    }
}

species reacteur parent: infrastructure {
    init {
        type <- "nuclear";
        max_age <- duree_de_vie["nuclear"];
        water_consumption <- factory_ressource["L water"]["nuclear"];
        land_usage <- factory_ressource["m² land"]["nuclear"];
        emission_factor <- emissions_per_kWh["nuclear"];
        color <- #red;
    }
}

species centrale_hydro parent: infrastructure {
    init {
        type <- "hydro";
        max_age <- duree_de_vie["hydro"];
        water_consumption <- factory_ressource["L water"]["hydro"];
        land_usage <- factory_ressource["m² land"]["hydro"];
        emission_factor <- emissions_per_kWh["hydro"];
        color <- #blue;
    }
}

species parc_eolien parent: infrastructure {
    float wind_factor <- 1.0;
    
    init {
        type <- "wind";
        max_age <- duree_de_vie["wind"];
        water_consumption <- factory_ressource["L water"]["wind"];
        land_usage <- factory_ressource["m² land"]["wind"];
        emission_factor <- emissions_per_kWh["wind"];
        color <- #green;
    }
    
    float get_current_production {
        if (!operational) {return 0.0;}
        
        string saison <- current_season();
        //float lat_factor <- location.x / world.shape.height;
        //wind_factor <- 0.8 + (lat_factor * 0.4);
        return factory_production[saison][type] * wind_factor;
    }
}

species champ_solaire parent: infrastructure {
    float sun_factor <- 1.0;
    
    init {
        type <- "solar";
        max_age <- duree_de_vie["solar"];
        water_consumption <- factory_ressource["L water"]["solar"];
        land_usage <- factory_ressource["m² land"]["solar"];
        emission_factor <- emissions_per_kWh["solar"];
        color <- #yellow;
    }
    
    float get_current_production {
        if (!operational) {return 0.0;}
        
        string saison <- current_season();
        float lat_factor <- location.y / world.shape.height;
        sun_factor <- 0.8 + (lat_factor * 0.4);
        return factory_production[saison][type] * sun_factor;
    }
}

//ENERGY

species energy parent:bloc{
	
	energy_producer producer <- nil;
	energy_consumer consumer <- nil;
	
	map<string, float> stock_E <- [];
	string op_last_action <- nil;
	string op_last_type <- nil;
	
	list<string> get_input_resources_labels{
		return production_inputs_E;
	}
	
	list<string> get_output_resources_labels{
		return production_outputs_E;
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	// SETUP
	
	action setup{
		list<energy_producer> producers <- [];
		list<energy_consumer> consumers <- [];
		create energy_producer number:1 returns:producers;
		create energy_consumer number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);
		
		stock_E["kWh energy"] <- 1.0;
		
		float total_land_needed <- 0.0;
		loop energy_type over: energy_types {
			total_land_needed <- total_land_needed + (park_FR[energy_type] * factory_construction_cost["m² land"][energy_type]);
		}
		
		if (producer.ext_producers contains_key "m² land") {
			bool land_ok <- producer.ext_producers["m² land"].producer.produce(["m² land"::total_land_needed]);
		}
		
		//Les species au lancement
		create reacteur number: park_FR["nuclear"] {
			location <- any_location_in(one_of(fronteers));
			age <- rnd(max_age);
		}
		
		create centrale_hydro number: park_FR["hydro"] {
			/* 
	          if (!empty(water_source)) {
	            location <- any_location_in(one_of(water_source));
			} else {
				location <- any_location_in(one_of(fronteers));
			}*/
			location <- any_location_in(one_of(fronteers));
			age <- rnd(max_age);
		}
		
		create parc_eolien number: park_FR["wind"] {
			location <- any_location_in(one_of(fronteers));
			age <- rnd(max_age);
			wind_factor <- 0.8 + rnd(0.4);
		}
		
		create champ_solaire number: park_FR["solar"] {
			location <- any_location_in(one_of(fronteers));
			age <- rnd(max_age);
			sun_factor <- 0.9 + rnd(0.2);
		}
		
		tick_production_E["kWh energy"] <- 0.0;
		tick_emissions_E["Total"] <- 0.0;
		tick_resources_used_E["L water"] <- 0.0;
		tick_resources_used_E["m² land"] <- 0.0;
		
		loop energy_type over: energy_types {
			tick_production_E[energy_type] <- 0.0;
			tick_emissions_E[energy_type] <- 0.0;
		}
		
		write "Parc initial créé :";
		write "  - Nucléaire: " + length(reacteur);
		write "  - Hydroélectrique: " + length(centrale_hydro);
		write "  - Éolien: " + length(parc_eolien);
		write "  - Solaire: " + length(champ_solaire);
	}
	
	map<string, float> get_stock_E{
		return stock_E;
	}
	
	//unused, on fait directement stock = stock + prod
	action set_stock_E(float s){
		stock_E["kWh energy"] <- s;
	}
	
	production_agent get_producer{
		return producer;
	}
	
	string current_season{
		int saison_index <- cycle mod 12;
		if(saison_index < 3) {return "spring";}
		else if(saison_index < 6) {return "summer";}
		else if(saison_index < 9) {return "autumn";}
		else {return "winter";}
	}
	
	map<string, float> get_production_by_type{
		map<string, float> production <- [];
		
		production["nuclear"] <- sum(reacteur collect (each.get_current_production()));
		production["hydro"] <- sum(centrale_hydro collect (each.get_current_production()));
		production["wind"] <- sum(parc_eolien collect (each.get_current_production()));
		production["solar"] <- sum(champ_solaire collect (each.get_current_production()));
		
		return production;
	}
	
	map<string, float> get_current_mix{
		map<string, float> current_mix <- [];
		map<string, float> production <- get_production_by_type();
		
		float total_prod <- 0.0;
		loop energy_type over: energy_types {
			total_prod <- total_prod + production[energy_type];
		}
		
		if (total_prod > 0.0) {
			loop energy_type over: energy_types {
				current_mix[energy_type] <- production[energy_type] / total_prod;
			}
		} else {
			loop energy_type over: energy_types {
				current_mix[energy_type] <- 0.0;
			}
		}
		
		return current_mix;
	}
	
	map<string, float> get_pollution_by_type{
		map<string, float> pollution <- [];
		
		pollution["nuclear"] <- sum(reacteur collect (each.get_current_emissions()));
		pollution["hydro"] <- sum(centrale_hydro collect (each.get_current_emissions()));
		pollution["wind"] <- sum(parc_eolien collect (each.get_current_emissions()));
		pollution["solar"] <- sum(champ_solaire collect (each.get_current_emissions()));
		
		return pollution;
	}
	
	map<string, float> get_resources_usage{
		map<string, float> resources <- ["L water"::0.0, "m² land"::0.0];
		
		resources["L water"] <- resources["L water"] + sum(reacteur collect (each.water_consumption));
		resources["L water"] <- resources["L water"] + sum(centrale_hydro collect (each.water_consumption));
		resources["L water"] <- resources["L water"] + sum(parc_eolien collect (each.water_consumption));
		resources["L water"] <- resources["L water"] + sum(champ_solaire collect (each.water_consumption));
		
		resources["m² land"] <- resources["m² land"] + sum(reacteur collect (each.land_usage));
		resources["m² land"] <- resources["m² land"] + sum(centrale_hydro collect (each.land_usage));
		resources["m² land"] <- resources["m² land"] + sum(parc_eolien collect (each.land_usage));
		resources["m² land"] <- resources["m² land"] + sum(champ_solaire collect (each.land_usage));
		
		return resources;
	}
	
	//Action
	
	action set_external_producer(string product, bloc bloc_agent){
		ask producer{
			do set_supplier(product, bloc_agent);
		}
	}
	
	action collect_last_tick_data{
		if(cycle > 0){
			tick_pop_consumption_E <- consumer.get_tick_consumption();
    		tick_resources_used_E <- producer.get_tick_inputs_used();
	    	tick_production_E <- producer.get_tick_outputs_produced();
	    	tick_emissions_E <- producer.get_tick_emissions();
	    	stock_E <- get_stock_E();
    	
	    	ask energy_consumer{
	    		do reset_tick_counters;
	    	}
	    	ask energy_producer{
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	action population_activity(list<human> pop){
		do optimize_park();
    	ask pop{
    		ask energy_consumer{
    			do consume(myself);
    		}
    	}
    	
    	ask energy_consumer{
    		ask energy_producer{
    			do stock_update();
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]);
		    	}
		    }
    	}
    }
    
    //Regarde si on peut construire puis construit
	action build_infrastructure(string energy_type, int quantity) {
	    loop mat over: ["m3_wood", "kg_cotton", "m² land"] {
	        float cost <- factory_construction_cost[mat][energy_type] * quantity;
	        
	        if (not(producer.ext_producers contains_key mat) or 
	            not(producer.ext_producers[mat].producer.produce([mat::cost]))) {
	            return; 
	        }
	    }
	    
	    //Création d'infrastructures
	    if (energy_type = "nuclear") {
	        create reacteur number: quantity {
	            location <- any_location_in(one_of(fronteers));
	            age <- 0.0;
	        }
	    } else if (energy_type = "hydro") {
	        create centrale_hydro number: quantity {
	        	/*
	            if (!empty(water_source)) {
	                location <- any_location_in(one_of(water_source));
	            } else {
	                location <- any_location_in(one_of(fronteers));
	            } */
	            location <- any_location_in(one_of(fronteers));
	            age <- 0.0;
	        }
	    } else if (energy_type = "wind") {
	        create parc_eolien number: quantity {
	            location <- any_location_in(one_of(fronteers));
	            age <- 0.0;
	            wind_factor <- 0.8 + rnd(0.4);
	        }
	    } else if (energy_type = "solar") {
	        create champ_solaire number: quantity {
	            location <- any_location_in(one_of(fronteers));
	            age <- 0.0;
	            sun_factor <- 0.9 + rnd(0.2); // A modifier
	        }
	    }
	}
	
	action count_surplus{
		surplus <- tick_production_E["kWh energy"] - tick_external_demand_E; //BIG modif
	}
	
	//On désactive l'usine la plus vieille 
	action remove_oldest_factory(string energy_type) {
	    list<infrastructure> candidates <- [];
	    
	    if (energy_type = "nuclear") { candidates <- reacteur select (each.operational); }
	    else if (energy_type = "hydro") { candidates <- centrale_hydro select (each.operational); }
	    else if (energy_type = "wind") { candidates <- parc_eolien select (each.operational); }
	    else if (energy_type = "solar") { candidates <- champ_solaire select (each.operational); }
	    
	    if (length(candidates) = 0) {
	        return;
	    }
	    infrastructure oldest <- candidates with_max_of (each.age);
	    ask oldest {
	        operational <- false;
	    }
	}
	
	// On réactive l'usine la plus jeune
	bool re_use_factory(string energy_type) {
	    list<infrastructure> unused <- [];
	    
	    if (energy_type = "nuclear") {unused <- reacteur select (not each.operational);}
	    else if (energy_type = "hydro") { unused <- centrale_hydro select (not each.operational);}
	    else if (energy_type = "wind") { unused <- parc_eolien select (not each.operational);}
	    else if (energy_type = "solar") { unused <- champ_solaire select (not each.operational);}
	    
	    if (length(unused) = 0) {
	        return false;
	    }
	    infrastructure youngest <- unused with_min_of (each.age);
	    ask youngest {
	        operational <- true;
	    }
	    return true;
	}
	
	// Construction/Destruction d'usines pour se rapprocher du mixeE
	action optimize_park {
	    float xsurplus <- surplus;
	    
	    // Paramètres
	    float TARGET_SURPLUS <- 1.5e7;
	    float STABLE_BAND <- 3.0e7;
	    
	    //Nombre d'infrastructures min
	    map<string,int> min_capacity <- [
	        "nuclear" :: 1,
	        "hydro" :: 1,
	        "wind" :: 1,
	        "solar" :: 1
	    ];
	    
	    //Nombre d'usines modifié max
	    map<string,int> batch_size <- [
	        "nuclear" :: 1,
	        "hydro" :: 26,
	        "wind" :: 30,
	        "solar" :: 13
	    ];
	    
	    write "surplus=" + xsurplus;
	    if (abs(xsurplus - TARGET_SURPLUS) <= STABLE_BAND) {
	        return;
	    }
	    map<string, float> current_mix <- get_current_mix();
	    
	    write "Mix actuel:";
	    loop energy_type over: energy_types {
	        write "  " + energy_type + ": " + (current_mix[energy_type] * 100.0) + "% (cible: " + (mix_E[energy_type] * 100.0) + "%)";
	    }
	    
	    //Sous production => On construit des usines
	    if (xsurplus < TARGET_SURPLUS - STABLE_BAND) {
	        
	        if (op_last_action = "destroy") {
	            return;
	        }
	        
	        //Trouver le type avec le plus grand écart négatif
	        string type_to_build <- nil;
	        float max_deficit <- 0.0;
	        
	        loop energy_type over: energy_types {
	            float deficit <- mix_E[energy_type] - current_mix[energy_type];
	            if (deficit > max_deficit) {
	                max_deficit <- deficit;
	                type_to_build <- energy_type;
	            }
	        }
	        
	        if (type_to_build = nil) {
	            type_to_build <- "solar";
	        }
	        
	        int batch <- batch_size[type_to_build];
	        int reused <- 0;
	        int built <- 0;
	        
	        loop times: batch {
	            if (re_use_factory(type_to_build)) {
	                reused <- reused + 1;
	            } else {
	                do build_infrastructure(type_to_build, 1);
	                built <- built + 1;
	            }
	        }
	        op_last_action <- "build";
	        op_last_type <- type_to_build;
	        return;
	    }
	    
	    //Sur production => On désactive des usines
	    if (xsurplus > TARGET_SURPLUS + STABLE_BAND) {
	        
	        if (op_last_action = "build") {
	            return;
	        }
	        
	        //Trouver le type avec le plus grand écart mixeE/mixe réel
	        string type_to_reduce <- nil;
	        float max_excess <- 0.0;
	        
	        loop energy_type over: energy_types {
	            float excess <- current_mix[energy_type] - mix_E[energy_type];
	            
	            //Verifier qu'on peut détruire
	            int current_count <- 0;
	            if (energy_type = "nuclear") { current_count <- length(reacteur select (each.operational)); }
	            else if (energy_type = "hydro") { current_count <- length(centrale_hydro select (each.operational)); }
	            else if (energy_type = "wind") { current_count <- length(parc_eolien select (each.operational)); }
	            else if (energy_type = "solar") { current_count <- length(champ_solaire select (each.operational)); }
	            
	            if (excess > max_excess and current_count > min_capacity[energy_type]) {
	                max_excess <- excess;
	                type_to_reduce <- energy_type;
	            }
	        }
	        
	        if (type_to_reduce != nil) {
	            int batch <- batch_size[type_to_reduce];
	            
	            loop times: batch {
	                do remove_oldest_factory(type_to_reduce);
	            }
	            
	            write "REDUCE " + type_to_reduce + " (excès=" + (max_excess*100.0) + "%): removed=" + batch;
	            op_last_action <- "destroy";
	            op_last_type <- type_to_reduce;
	        }
	    }
	}
}

//ENERGY PRODUCER
species energy_producer parent:production_agent{
	
	map<string, float> tick_resources_used <- map<string, float>([]);
	map<string, float> tick_production <- map<string, float>([]);
	map<string, float> tick_emissions <- map<string, float>([]);
	
	map<string, bloc> ext_producers <- [];
	
	//GETTER
	map<string, float> get_tick_inputs_used{
		return copy(tick_resources_used);
	}
	
	map<string, float> get_tick_outputs_produced{
		return copy(tick_production);
	}
	
	map<string, float> get_tick_emissions{
		return copy(tick_emissions);
	}
	
	//SETTER
	action set_tick_resources_used(map<string, float> new_resources){
		tick_resources_used["m² land"] <- new_resources["m² land"];
		tick_resources_used["L water"] <- new_resources["L water"];
    }
    
    action set_tick_production(map<string, float> new_resources){
        tick_production <- new_resources;
    }
    
    action set_tick_emissions(map<string, float> new_resources){
        tick_emissions <- new_resources;
    }
	
	//RESET
	action reset_tick_counters{
		tick_production["kWh energy"] <- 0.0;
		tick_external_demand_E <- 0.0;
		tick_consommee <- 0.0;
		
		loop energy_type over: energy_types {
			tick_production[energy_type] <- 0.0;
			tick_emissions[energy_type] <- 0.0;
		}
		
		tick_emissions["Total"] <- 0.0;
		tick_resources_used["L water"] <- 0.0;
		tick_resources_used["m² land"] <- 0.0;
		
		loop c over: production_outputs_E {
			tick_pop_consumption_E[c] <- 0;
		}
	}
	
	//PRODUCE
	bool produce(map<string, float> demand){
		bool ok <- true;
		
		loop product over: demand.keys {
			if (product = "kWh energy"){
				tick_external_demand_E <- tick_external_demand_E + demand[product];
			}
		}
		
		loop product over: demand.keys {
			ask energy {
				if(demand[product] > stock_E[product]) {
					ok <- false;
				}
			}
		}
		
		if(ok) {
			loop product over: demand.keys {
				ask energy {
					stock_E[product] <- stock_E[product] - demand[product];
					tick_consommee <- tick_consommee + demand[product];
				}
			}
		}
		
		ask energy {
			do count_surplus();
		}
		
		return ok;
	}
	
	action stock_update{
		map<string, float> prod <- map<string, float>([]);
	    map<string, float> poll <- map<string, float>([]);
	    
		ask energy {
			
            map<string, float> production_by_type <- get_production_by_type();
            map<string, float> pollution_by_type <- get_pollution_by_type();

            loop energy_type over: energy_types {
                prod[energy_type] <- production_by_type[energy_type];
                poll[energy_type] <- pollution_by_type[energy_type];
            }
            
            float total_kWh <- 0.0;
            float total_pollution <- 0.0;
            loop energy_type over: energy_types {
                total_kWh <- total_kWh + production_by_type[energy_type];
                total_pollution <- total_pollution + pollution_by_type[energy_type];
            }
            stock_E["kWh energy"] <- stock_E["kWh energy"] + total_kWh;
            prod["kWh energy"] <- total_kWh;
            poll["Total"] <- total_pollution;
        }
        
	    map<string, float> ress <- map<string, float>([]);

	    ask energy {
		    ress <- get_resources_usage();
	    }
	 	bool av <- ext_producers["L water"].producer.produce(["L water"::ress["L water"]]);
	 	
	 	if(av) {
	 		ask energy {
	 			stock_E["kWh energy"] <- stock_E["kWh energy"] + prod["kWh energy"];
	 		}
	 		
	 		tick_production["kWh energy"] <- tick_production["kWh energy"] + prod["kWh energy"];
	 		tick_resources_used["L water"] <- tick_resources_used["L water"] + ress["L water"];
	 		tick_resources_used["m² land"] <- tick_resources_used["m² land"] + ress["m² land"];
	 		tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + poll["Total"];
	 		
	 		do set_tick_production(prod);
	 		do set_tick_resources_used(ress);
	   		do set_tick_emissions(poll);
	 	}
	}
	
	action set_supplier(string product, bloc bloc_agent){
		ext_producers[product] <- bloc_agent;
	}
}

//ENERGY CONSUMER 

species energy_consumer parent:consumption_agent{

	map<string, float> consumed <- [];
	
	map<string, float> get_tick_consumption{
		return copy(consumed);
	}
	
	init{
		loop c over: production_outputs_E {
			consumed[c] <- 0;
		}
	}
	
	action reset_tick_counters{
		loop c over: consumed.keys {
			consumed[c] <- 0;
		}
	}
	
	action consume(human h){
		string saison;
		ask energy {
			saison <- current_season();
		}
		
	    string choice <- one_of(production_outputs_E);
		consumed[choice] <- consumed[choice] + rnd(min_kWh_conso[saison], max_kWh_conso[saison]);
	}
}

//AFFICHAGE

experiment run_energy type: gui {
    
    output {
		display Energy_information {
			chart "Écart Production / Consommation" type: series size: {0.5, 0.5} position: {0, 0} {
			    data "Demande externe" value: tick_external_demand_E color: #black;
			    data "Consommation totale" value: tick_consommee color: #blue;
			    data "Production" value: tick_production_E["kWh energy"] color: #green;
			    data "Surplus" value: surplus color: #red;
			}
			
			chart "Production par type (kWh)" type: series size: {0.5, 0.5} position: {0.5, 0} {
			    data "Nucléaire" value: tick_production_E["nuclear"] color: #red;
			    data "Hydroélectrique" value: tick_production_E["hydro"] color: #blue;
			    data "Éolien" value: tick_production_E["wind"] color: #green;
			    data "Solaire" value: tick_production_E["solar"] color: #yellow;
			    data "Total" value: tick_production_E["kWh energy"] color: #black;
			}
			
			chart "Ressources utilisées" type: series size: {0.5, 0.5} position: {0, 0.5} {
				data "Terre (m²)" value: tick_resources_used_E["m² land"] color: #brown;
				data "Eau (L)" value: tick_resources_used_E["L water"] color: #blue;
			}
			
			chart "Émissions (gCO2e)" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
			    data "Nucléaire" value: tick_emissions_E["nuclear"] color: #red;
			    data "Hydroélectrique" value: tick_emissions_E["hydro"] color: #blue;
			    data "Éolien" value: tick_emissions_E["wind"] color: #green;
			    data "Solaire" value: tick_emissions_E["solar"] color: #yellow;
			    data "Total" value: tick_emissions_E["Total"] color: #black;
			}
	    }
	    
	    display Energy_map type: java2D {
	        species fronteers aspect: base;
	        species water_source aspect: base transparency: 0.3;
	        species reacteur aspect: base;
	        species centrale_hydro aspect: base;
	        species parc_eolien aspect: base;
	        species champ_solaire aspect: base;
	    }
	}
}
