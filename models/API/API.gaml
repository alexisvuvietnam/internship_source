/**
* Name: API (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/
model API

/*
 * Species used to represent a bloc.
 * A bloc as the following main functions :
 *  - be the interface between its producers and the other blocs
 *  - define the consumption behavior of the population related to this bloc
 * See the example blocs supplied alongside the API for more details.
 */
species bloc {
	string name; // the name of the bloc
	production_agent producer; // the production agent of the bloc

	/* Initialize the bloc */
	action setup virtual: true;

	/* Execute the next tick */
	action tick (list<human> pop) virtual: true;

	/* Returns the labels of the resources used by this bloc for production (inputs) */
	action get_input_resources_labels virtual: true type: list<string>;

	/* Returns the labels of the resources produced by this bloc (outputs) */
	action get_output_resources_labels virtual: true type: list<string>;
}

/* 
 * Species used to represent all the production of a bloc.
 * Note : this species will be implemented as a micro-species of its bloc.
 * See the example blocs supplied alongside the API for more details.
 */
species production_agent {
	
	float proba_vacation <- 0.33;//Approximately one over three days per years are day-off. 
	bool is_day_off <- false;
	
	reflex go_to_work {
		is_day_off <- flip(proba_vacation);
	}

/* Produce the given resources in the requested quantities. Return true in case of success. */
	action produce (map<string, float> demand) virtual: true type: bool;

	/* Returns all the resources used for the production this tick */
	action get_tick_inputs_used virtual: true type: map<string, float>;

	/* Returns the amounts produced this tick */
	action get_tick_outputs_produced virtual: true type: map<string, float>;

	/* Returns the amounts emitted this tick */
	action get_tick_emissions virtual: true type: map<string, float>;

	/* Defines an external producer for a resource */
	action set_supplier (string product, bloc bloc_agent) virtual: true;
}

/* 
 * Species used to detail the consumption behavior of the population, related to a bloc.
 * Every tick, this behavior will be applied to all the individuals of the population.
 * Note : this species will be implemented as a micro-species of its bloc.
 * See the example blocs supplied alongside the API for more details.
 */
species consumption_agent {

/* Apply the consumption behavior of a given human. Return true in case of success. */
	action consume (human h) virtual: true;

	/* Returns the amount of resources consumed by the population this tick */
	action get_tick_consumption virtual: true type: map<string, float>;
}

species human {
	int age <- 0; // age (in years)
	string gender <- ""; // gender
	map<string, string> additional_attributes <- [];
}

/* 
 * Species used to implement the coordinator agent of the simulation.
 * This is a unique agent in charge of the following tasks :
 * - register all the instanciated blocs
 * - link the producers with their suppliers
 * - execute each tick, coordinating blocs and other agents
 * This agent is not intended to be modified. If this is the case, please check beforehand the possible 
 * side effects of the modifications on the system as a whole.
 */
species coordinator {
	map<string, bloc> registered_blocs <- []; // the blocs handled by the coordinator
	map<string, bloc> producers <- []; // the producer registered for each resource
	list<string> scheduling <- []; // blocs execution order
	bool started <- false; // the current state of the coordinator (started or waiting)

	/* Returns all the agents of a given species and its subspecies */
	list<agent> get_all_instances (species<agent> spec) {
		return spec.population + spec.subspecies accumulate (get_all_instances(each));
	}

	/* Register a bloc : it will be handled by the coordinator */
	action register_bloc (bloc b) {
		list<string> products <- [];
		ask b {
			do setup; // setup the bloc
			products <- get_output_resources_labels();
		}

		registered_blocs[b.name] <- b;
		loop p over: products { // register this bloc as producer of product p
			producers[p] <- b;
		}

		if !(b.name in scheduling) {
			scheduling <- scheduling + b.name;
		}

	}

	/* Affects the external producers (when a bloc needs the production of another bloc, this one is its exernal producer) */
	action affect_suppliers {
		loop b over: registered_blocs.values {
			list<string> resources_used <- b.get_input_resources_labels();
			loop r over: resources_used {
				if (producers.keys contains r) { // there is a known producer for this resource/good
					ask b.producer {
						do set_supplier(r, myself.producers[r]); // link the external producer to the bloc needing it
					}

				}

			}

		}

	}

	/* Defines the scheduling of the different blocs */
	action set_scheduling (list<string> scheduling_order) {
		scheduling <- scheduling_order;
	}

	/* Register all the blocs */
	action register_all_blocs {
		list<bloc> blocs <- get_all_instances(bloc);
		loop b over: blocs {
			do register_bloc(b); //register the bloc
		}

		write "registered blocs : " + registered_blocs;
		if length(scheduling) = 0 {
			scheduling <- blocs collect each.name; // set default scheduling order
		}

		do affect_suppliers();
	}

	/* Start the simulation */
	action start {
		started <- true;
	}

	/* Stop the simulation */
	action stop {
		started <- false;
	}

	/* Reflex : move to the next tick of the simulation */
	reflex new_tick when: started {
		list<human> pop <- get_all_instances(human);
		loop bloc_name over: scheduling { // move to next tick for all blocs, following the defined scheduling
			if bloc_name in registered_blocs.keys {
				ask registered_blocs[bloc_name] {
					do tick(pop);
				}

			} else {
				write "warning : bloc " + bloc_name + " not found !";
				// if you have this warning, check that the name of the blocs in the scheduling are correct
			}

		}

	}

}

/* Territory species (used to represent GIS elements) */
species fronteers {
	string type;
	rgb color <- #whitesmoke;
	rgb border_color <- #dimgray;

	aspect base {
		draw shape color: color border: border_color;
	}

}

species mountain {
	string type;
	rgb color <- #silver;

	aspect base {
		draw shape color: color;
	}

}

species forest {
	string type;
	rgb color <- #mediumseagreen;

	aspect base {
		draw shape color: color;
	}

}

species water_source {
	string type;
	rgb color <- #royalblue;

	aspect base {
		draw shape color: color;
	}

}

//species city {
//	string type;
//	rgb color <- #black;
//
//	aspect base {
//		draw circle(2.0 #px) color: color;
//	}
//
//}

/*
 * Species used for the generation of cities and mini-cities
 */
species cities {
	file shape_file_cities;
	geometry shape;
	// Parameters for city generation asked to user :
	int population_size; // number of people in the simulation
	int number_of_mini_cities; // number of mini-cities
	int city_population; // number of people per constellations of mini-cities
	int number_of_cities;
	int nb_mini_cities_per_city;
	int mini_city_population <- 10000; // population of a mini-city (10000 by default according to CDC)
	list<mini_city> mini_cities; // list of all mini-cities
	list<main_city> main_cities; // list of all main-cities
	float mini_city_distance_from_center <- 5.0 #km;

	action generate_cities {
		write(city_population);
		// 1. create cities (mini-city constellations)
		create main_city from: shape_file_cities with: [city_name::read("name"), city_population::city_population];
		main_cities <- list(main_city);
		number_of_cities <- length(main_city);
		nb_mini_cities_per_city <- int(city_population / mini_city_population);

		// 2. create mini-cities around each constellations
		ask main_city {
			do generate_mini_cities(myself.nb_mini_cities_per_city, myself.mini_city_distance_from_center, myself.mini_city_population);
		}
		mini_cities <- list(mini_city);
	}

	list<mini_city> get_mini_cities {
		return mini_cities;
	}

	list<main_city> get_main_cities {
		return main_cities;
	}
}

/*
 * Species of a main_city representing a main city of France (one of the cities given in the file 'cities_france.shp'
 * It serves as a point of reference for the placement of a constellations of mini-cities around it 
 */
species main_city {
	string city_name;
	int city_population <- 0;
	list<mini_city> mini_cities_list;

	action generate_mini_cities (int nb_mini_cities_per_city, float mini_city_distance_from_center, int mini_city_population) {
		loop i from: 0 to: nb_mini_cities_per_city - 1 {
			// Calculate the position for GIS
			// Angle evenly spaced around the center 
			// TODO : changer le placement des villes pour un placement aléatoire dans un rayon
			float angle <- i * (360.0 / nb_mini_cities_per_city);
			// Position with small random noise
			float distance <- mini_city_distance_from_center * (0.8 + rnd(0.4));
			float angle_noise <- angle + rnd(-15.0, 15.0);
			point offset <- {distance * cos(angle_noise), distance * sin(angle_noise)};
			point mini_city_location <- location + offset;
			
			create mini_city {
				mini_city_name <- myself.city_name + "_MC" + i;
				location <- mini_city_location;
				parent_city <- myself; //reference to its parent
				radius <- 1 #km; // radius of mini-cities
				pop <- mini_city_population;
				add self to: myself.mini_cities_list;
			}
		}
	}
	// --- GIS
	aspect base {
		draw circle(1000) color: #darkgray border: #black;
		draw city_name color: #black size: 16 font: font("Arial", 16, #bold) at: location + {0, -1200};
	}

}

/* 
 * Species of mini-city created from a main city of France (metropolitan)
 * it possesses a reference to its parent city, which is taken as a point of reference to place major
 * transport axes later on
 */
species mini_city {
	string mini_city_name;
	main_city parent_city;
	float radius;
	float surface <- radius * radius * 3.14; // Calcul de la surface
	int pop <- 0 min: 40 max: 50000; // de 40 à 50000 habitants
	list<mini_city> connected_mini_cities;
	
	// Urbanisme
	map<string, float> building_supply <- [];
	map<string, float> potential_building_supply <- [];
	
	map<string, float> demand <- [];
	map<string, float> shortage <- [];
	map<string, list> building_queue <- [];
	
	
	map<string, float> tick_resources_used <- [];
	map<string, float> tick_production <- [];
	map<string, float> tick_emissions <- [];
	map<string, float> tick_demand <- [];
	
	int go_to_school;
	int go_to_work;
	

	// --- GIS
	int degree update: length(connected_mini_cities);

	aspect base {
	// color variation depending on connectivity
		rgb node_color <- rgb(255 - min([255, degree * 30]), 100 + min([155, degree * 20]), 100);
		draw circle(radius) color: node_color border: #black;
		draw name color: #black size: 10 at: location + {0, radius + 100};
	}

	aspect degree {
		draw circle(radius) color: #white border: #black;
		draw string(degree) color: #black size: 14 font: font("Arial", 14, #bold);
	}
}



