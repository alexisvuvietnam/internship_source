/**
* Name: Main (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/
model Main

import "API/API.gaml"
import "blocs/Demography.gaml"
import "blocs/Agricultural.gaml"
import "blocs/Energy.gaml"
import "blocs/Transport.gaml"
import "blocs/Urbanplanning.gaml"
import "blocs/Environnement.gaml"

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
	int mini_city_population;
	list<mini_city> mini_cities; // list of all mini-cities
	list<main_city> main_cities; // list of all main-cities
	float mini_city_distance_from_center <- 20.0 #km;

	action generate_cities {
	// 1. create cities (mini-city constellations)
		create main_city from: shape_file_cities with: [city_name::read("name"), city_population::city_population];
		main_cities <- list(main_city);
		number_of_cities <- length(main_city);
		nb_mini_cities_per_city <- int(city_population / mini_city_population);

		// 2. create mini-cities around each constellations
		ask main_city {
			loop i from: 0 to: nb_mini_cities_per_city - 1 {
			// Calculate the position for GIS
			// Angle evenly spaced around the center 
			// TODO : changer le placement des villes pour un placement aléatoire dans un rayon
				float angle <- i * (360.0 / nb_mini_cities_per_city);
				// Position with small random noise
				float distance <- myself.mini_city_distance_from_center * (0.8 + rnd(0.4));
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

		mini_cities <- list(mini_city);
	}

}
/**
 * Main section with aggregated population system.
 * Population is controlled through city parameters and represented as integers.
 */
global {
// Population control parameters
	int number_of_mini_cities <- 100; // Number of mini-cities
	int mini_city_population <- 10000; // Average population per mini-city

	// Population initiale
	int population_size <- 667930; // Population réelle 66793000 (facteur x100)

	// City constellation parameters
	int city_population <- int(population_size / 49); // 49 villes principales d'après le shapefile
	int nb_mini_cities_per_city update: int(city_population / mini_city_population);
	int nb_mini_cities <- length(mini_city);
	bool use_gis <- true;
	float step <- 1 #month;
	bool enable_demography <- true; // TODO supprimer cette ligne
	map<string, int> counts; // Compte le nombre d'agents de chaque type

	// GIS files
	file shape_file_cities <- file("../includes/shapefiles/cities_france.shp");
	file shape_file_bounds <- file("../includes/shapefiles/boundaries_france.shp");
	file shape_file_forests <- file("../includes/shapefiles/forests_france_light.shp");
	file shape_rivers_lakes <- file("../includes/shapefiles/rivers_france_light.shp");
	file shape_mountains <- file("../includes/shapefiles/mountains_france_1300m.shp");
	geometry shape <- envelope(shape_file_bounds);
	geometry shape_cities <- envelope(shape_file_cities);

	// Sector data
	float surface_used_agri <- 0.0;
	float surface_used_env <- 0.0;
	float surface_used_energy <- 0.0;
	float water_used_agri <- 0.0;
	float water_used_energy <- 0.0;
	float energy_used_agri <- 0.0;
	float energy_used_urban <- 0.0;
	float energy_used_transport <- 0.0;
	float GES_emissions_agri <- 0.0;
	float GES_emissions_env <- 0.0;
	float GES_emissions_energy <- 0.0;
	float GES_emissions_urban <- 0.0;
	cities city_generator;
	list<mini_city> mini_cities;
	list<main_city> main_cities;

	init {
		if (use_gis) {
		// Setup territory with GIS
			create fronteers from: shape_file_bounds;
			create mountain from: shape_mountains;
			create forest from: shape_file_forests;
			create water_source from: shape_rivers_lakes;
			nb_mini_cities_per_city <- int(city_population / mini_city_population);
			create cities number: 1 with:
			[shape_file_cities::shape_file_cities, city_population::city_population, number_of_mini_cities::number_of_mini_cities, population_size::population_size, mini_city_population::mini_city_population, nb_mini_cities_per_city::nb_mini_cities_per_city];
			ask cities {
				do generate_cities();
			}

			ask cities {
				myself.mini_cities <- mini_cities;
				myself.main_cities <- main_cities;
			}

			write "Created " + length(mini_cities) + " mini-cities with total initial population: " + sum(mini_cities collect each.pop);
		} else {
		// Generate cities without GIS for demographic purposes
			nb_mini_cities_per_city <- int(city_population / mini_city_population);

			// Create mini_cities with initial population
			loop i from: 0 to: number_of_mini_cities - 1 {
				create mini_city {
					mini_city_name <- "City_" + i;
					pop <- mini_city_population;
					location <- {rnd(100), rnd(100)};
					radius <- 1 #km;
				}

			}

			mini_cities <- list(mini_city);
			write "Created " + length(mini_cities) + " mini-cities with total initial population: " + sum(mini_cities collect each.pop);
		}

		// Create residents bloc with city references
		// No individual agents will be created - population is aggregated at city level
		create residents number: 1 with: [enabled::enable_demography, total_population::population_size, nb_mini_cities::length(mini_city)];

		// Other blocs can access population through mini_cities or total population
		create agricultural number: 1 {
			pop_size <- int(population_size/100);
			prop_human <- 100;
		}

		create energy number: 1;
		create urbanplanning number: 1 {
			mini_cities <- myself.mini_cities;
		}

		create transport number: 1 with:
		// [use_gis::use_gis, mini_cities::mini_cities, main_cities::main_cities, city_population::city_population, nb_mini_cities_per_city::nb_mini_cities_per_city, mini_city_population::mini_city_population];
		[mini_cities::mini_cities, main_cities::main_cities, city_population::city_population, nb_mini_cities_per_city::nb_mini_cities_per_city, mini_city_population::mini_city_population];
		create environnement number: 1 {
			population <- population_size;
		}

		create coordinator number: 1;
		ask coordinator {
			do register_all_blocs;
			do start;
		}

	}

	reflex update_agents_species {
		counts <- [];
		loop ag over: world.agents {
			string s <- species(ag);
			counts[s] <- counts[s] + 1;
		}

	}

}

/**
 * GIS display experiment
 */
experiment display_gis type: gui {
	parameter "Nombre de mini-villes :" var: number_of_mini_cities category: 'Model' min: 1;
	parameter "Population par mini-ville :" var: mini_city_population category: 'Model' min: 100;
	parameter "Nombre d'individus par constellation :" var: city_population category: 'Model';
	output {
		display country_map type: java2D {
			species fronteers aspect: base;
			species mountain aspect: base transparency: 0.15;
			species forest aspect: base transparency: 0.15;
			species water_source aspect: base;
			species mini_city aspect: base;
			species main_city aspect: base;
			species transport_link aspect: base;
		}

	}

}

/**
 * Main experiment with population monitoring
 */
experiment main_experiment type: gui {
	parameter "Taille de la population :" var: population_size category: 'Model' min: 1;
	parameter "Population par mini-ville (initial) :" var: mini_city_population category: 'Model' min: 100;
	output {
	// Population monitors
		monitor "Population totale actuelle" value: population_size;
		monitor "Nombre de mini-villes" value: length(mini_city);
		monitor "Population moyenne par ville" value: length(mini_city) > 0 ? int(population_size / length(mini_city)) : 0;

		// Resource monitors
		monitor "Énergie consommée agriculture" value: world.tick_resources_used_A["kWh energy"];
		monitor "Énergie consommée urbanisme" value: world.tick_resources_used_U["kWh energy"];
		monitor "Énergie consommée transport" value: world.tick_resources_used_T["kWh energy"];
		monitor "Eau consommée agriculture" value: world.tick_resources_used_A["L water"];
		monitor "Eau consommée énergie" value: world.tick_resources_used_E["L water"];
		monitor "GES émis agriculture" value: world.tick_emissions_A["gCO2e emissions"];
		monitor "GES émis urbanisme" value: world.tick_emissions_U["gCO2e emissions"];
		monitor "GES émis énergie" value: world.tick_emissions_E["gCO2e emissions"];
		monitor "GES émis transport" value: world.tick_emissions_T["gCO2e emissions"];
		monitor "GES absorbés par l'environnement" value: world.tick_absorbed_ECO["gCO2e emissions"];
		monitor "Surface disponible totale" value: world.available_surface;

		// Les agents de la simulation
		monitor "Nombre d'agents total" value: length(world.agents);
		monitor "Nombre d'agents par type" value: counts;
		monitor "Bloc faisant demandes de coton" value: cotton_buyers_A["energy0"];

		// Energy consumption displays
		display "Répartition de la consommation d'énergie pour chaque secteur" type: 2d {
			chart "Consommation d'énergie pour chaque secteur" type: pie {
				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #orange;
				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
			}

		}

		display "Évolution de la consommation d'énergie pour chaque secteur" type: 2d {
			chart "Évolution de la consommation d'énergie pour chaque secteur" type: series {
				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #orange;
				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
			}

		}

		// Water consumption displays
		display "Répartition de la consommation d'eau pour chaque secteur" type: 2d {
			chart "Consommation d'eau pour chaque secteur" type: pie {
				data "Agriculture" value: world.tick_resources_used_A["L water"] color: #orange;
				data "Énergie" value: world.tick_resources_used_E["L water"] color: #yellow;
			}

		}

		display "Évolution de la consommation d'eau pour chaque secteur" type: 2d {
			chart "Évolution de la consommation d'eau pour chaque secteur" type: series {
				data "Agriculture" value: world.tick_resources_used_A["L water"] color: #orange;
				data "Énergie" value: world.tick_resources_used_E["L water"] color: #yellow;
			}

		}

		// GHG emissions displays
		display "Répartition de la production de GES pour chaque secteur" type: 2d {
			chart "Quantité de GES émis pour chaque secteur (en grammes)" type: pie {
				data "Agriculture" value: world.tick_emissions_A["gCO2e emissions"] color: #orange;
				data "Urbanisme" value: world.tick_emissions_U["gCO2e emissions"] color: #gray;
				data "Energie" value: world.tick_emissions_E["gCO2e emissions"] color: #yellow;
			}

		}

		display "Évolution de l'émission de GES pour chaque secteur" type: 2d {
			chart "Évolution de l'émission de GES pour chaque secteur (en grammes)" type: series {
				data "Agriculture" value: world.tick_emissions_A["gCO2e emissions"] color: #orange;
				data "Urbanisme" value: world.tick_emissions_U["gCO2e emissions"] color: #gray;
				data "Energie" value: world.tick_emissions_E["gCO2e emissions"] color: #yellow;
				data "Transport" value: world.tick_emissions_T["gCO2e emissions"] color: #blue;
				data "Environnement" value: world.tick_absorbed_ECO["gCO2e emissions"] color: #green;
				data "Total" value:
				world.tick_emissions_A["gCO2e emissions"] + world.tick_emissions_U["gCO2e emissions"] + world.tick_emissions_E["gCO2e emissions"] + world.tick_emissions_T["gCO2e emissions"] + world.tick_absorbed_ECO["gCO2e emissions"]
				color: #black;
			}

		}

	}

}