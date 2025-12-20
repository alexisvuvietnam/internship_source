/**
* Name: Transport
* Based on the internal empty template. 
* Author: williamsardon
* Tags: 
*/


model Transport_GIS
import "../API/API.gaml"

global {
	/* Data used to instatiate */
	// TODO : ARBITRARY VALUES TO REPLACE
	float max_capacity_highway <- 200.0;
	float max_capacity_main_road <- 100.0;
	float max_capacity_local_road <- 50.0;
	
	// min length of a road to be determined a certain type (highway, main_road or local_road)
	float min_length_highway <- 10.0#km;
	float min_length_main_road <- 5.0#km;
	
	/* Setup */
	list<string> production_inputs_T <- ["kWh energy"];
	list<string> production_outputs_T <- ["minibus", "train", "truck", "taxi"];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	
	/* Production data */
	// TODO : concerne les fabrication de nouveaux véhicules
	//	map<string, map<string, float>> production_outputs_inputs_T <-
	//	["minibus" :: ["kWh energy" :: 0.0, "kg plastic" :: 0.0],  
	//	"train" :: ["kWh energy" :: 0.0, "kg plastic" :: 0.0],
	//	"taxi" :: ["kWh energy" :: 0.0, "kg plastic" :: 0.0]];
	//	map<string, map<string, float>> production_output_emissions_T <- 
	//	["minibus" :: ["gCO2e emissions" :: 0.0],
	//	"train" :: ["gCO2e emissions" :: 0.0],
	//	"taxi" :: ["gCO2e emissions" :: 0.0]];
	
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
species transport_gis parent:bloc{
	string name <- "transport";
	
	transport_producer_gis producer <- nil;
	transport_consumer_gis consumer <- nil;
	
	// demography informations
	list<mini_city> mini_cities <- [];
	list<main_city> main_cities <- [];
	
	int nb_mini_cities_per_city;
	int mini_city_population <- 10000;
	int city_population;
    graph transport_network;
    
    // parameters of Small-World (Watts-Strogatz) for the creation of the network
    int k_neighbors;
    float rewiring_probability <- 0.0; // TODO: at 0 for now because of an error in the deletion of transport link
	
	action setup{
		list<transport_producer_gis> producers <- [];
		list<transport_consumer_gis> consumers <- [];
		create transport_producer_gis number:1 returns:producers;
		create transport_consumer_gis number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);
		
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
		write "K voisins calculé: " + k_neighbors;
		// generate small-world
        write "Génération du réseau...";
        do create_network();
        
        write "Création de " + length(transport_link) + " liens de transport";
        
        // add inter city links
        do add_inter_city_links();
        // rebuild the graph
        transport_network <- as_edge_graph(list(transport_link));
        write "Réseau de transport généré avec succès";
        
        write "Nombre d'autoroutes : " + length(list(transport_link where (each.link_type = "highway")));
        write "Nombre de routes principales : " + length(list(transport_link where (each.link_type = "main_road")));
        write "Nombre de routes locales : " + length(list(transport_link where (each.link_type = "local_road")));
	}
	
	action create_network {
	    // link the k closest cities
	    loop i from: 0 to: length(mini_cities)-1 {
	        mini_city node_i <- mini_cities[i];
	        // order the other cities according to their proximity to mini city i (node_i)
	        list<mini_city> neighbors <- mini_cities 
	            where (each != node_i)
	            sort_by (each.location distance_to node_i.location);
	        // connect to the k firts
	        loop j from: 0 to: min([k_neighbors-1, length(neighbors)-1]) {
	            mini_city node_j <- neighbors[j];
	            // verify if the link exists
	            if !link_exists(node_i, node_j) {
	            	string type <- determine_link_type(node_i, node_j);
                	// verify there are no highway already between the two constellations
                	if type = "highway"{
                		if highway_exists(node_i, node_j){
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
	            list<mini_city> far_nodes <- mini_cities 
	                where (each != node_a and 
	                       each != node_b and
	                       (each.location distance_to node_a.location) > min_length_main_road);
	            
	            if !empty(far_nodes) {
	                mini_city new_target <- one_of(far_nodes);
	                if !link_exists(node_a, new_target) and new_target!=nil and node_a!=nil{
	                    // delete the old link
	                    ask link { do die; }
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
    	
	    	ask transport_consumer_gis{ // prepare next tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask transport_producer_gis{ // prepare next tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{
    		ask myself.transport_consumer_gis{
    			do consume(myself);
    		}
    	}
    	 
    	ask transport_consumer_gis{ // produce the required quantities
    		ask transport_producer_gis{
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]);
		    	}
		    } 
    	}
    }

	species transport_producer_gis parent:production_agent{
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
	
	species transport_consumer_gis parent:consumption_agent{
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
	
	action add_inter_city_links {
        // connect main cities between each other
        loop i from: 0 to: length(main_cities) - 1 {
            main_city city_i <- main_cities[i];
            // find 2-3 closest cities
            list<main_city> nearest_cities <- main_cities 
                where (each != city_i)
                sort_by (each.location distance_to city_i.location);
            
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
    
    bool highway_exists(mini_city a, mini_city b) {
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
    action determine_link_type(mini_city a, mini_city b) type: string {
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
    bool link_exists(mini_city a, mini_city b) {
        return !(empty(transport_link where (
            (each.node_a = a and each.node_b = b) or
            (each.node_a = b and each.node_b = a)
        )));
    }
    
    action get_link(mini_city a, mini_city b) type: transport_link{
    	if link_exists(a, b){
    		return first(transport_link where (
    		(each.node_a = a and each.node_b = b) or
            (each.node_a = b and each.node_b = a)));
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
    
    aspect default {
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

/**
 * We define here the experiment and the displays related to transport. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_transport_gui type: gui {
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