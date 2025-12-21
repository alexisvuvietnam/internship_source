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
// import "blocs/Transport_GIS.gaml"
import "blocs/Transport.gaml"
import "blocs/Urbanplanning.gaml"
import "blocs/Environnement.gaml"

/**
 * This is the main section of the simulation. Here, we instanciate our blocs, and launch the simulation through the coordinator.
 */
global {
// parameters for city generation
	int population_size <- 1000000; // number of people in the simulation
	int number_of_mini_cities <- 100; // number of mini-cities
	int city_population <- 70000; // number of people per city (constellations of mini-cities)
	bool use_gis <- false; // use GIS or not (needed to spatialise, instanciate territory species, and to display the map)
	float step <- 1 #month; // the simulation step is a month
	bool enable_demography <- true; // true to activate the demography (births, deaths), else false

	// GIS files
	file shape_file_cities <- file("../includes/shapefiles/cities_france.shp");
	file shape_file_bounds <- file("../includes/shapefiles/boundaries_france.shp");
	file shape_file_forests <- file("../includes/shapefiles/forests_france_light.shp");
	file shape_rivers_lakes <- file("../includes/shapefiles/rivers_france_light.shp");
	file shape_mountains <- file("../includes/shapefiles/mountains_france_1300m.shp");
	geometry shape <- envelope(shape_file_bounds);
	geometry shape_cities <- envelope(shape_file_cities);

	// Données pour chaque secteur

	// Surface
	float surface_used_agri <- 0.0;
	float surface_used_env <- 0.0;
	float surface_used_city <- 0.0;
	float surface_used_energy <- 0.0;

	// Eau
	float water_used_agri <- 0.0;
	float water_used_energy <- 0.0;
	float water_used_city <- 0.0;

	// Énergie
	float energy_used_agri <- 0.0;
	float energy_used_urban <- 0.0;
	float energy_used_transport <- 0.0;

	// GES émis
	float GES_emissions_agri <- 0.0;
	float GES_emissions_env <- 0.0;
	float GES_emissions_city <- 0.0;
	float GES_emissions_energy <- 0.0;
	float GES_emissions_urban <- 0.0;

	init {
		if (use_gis) {
		// setup the territory :
			create fronteers from: shape_file_bounds;
			create mountain from: shape_mountains;
			create forest from: shape_file_forests;
			create water_source from: shape_rivers_lakes;
		}

		// instanciate the blocs (E, A and R blocs here):
		create residents number: 1 {
			enabled <- enable_demography;
		}

		create agricultural number: 1 {
			pop_size <- population_size;
		}

		create energy number: 1;
		create urbanplanning number: 1;
		create transport number: 1;

		// L'environnement gère les mini-villes
		create environnement number: 1 {
			population <- population_size;
			nb_mini_cities <- number_of_mini_cities;
		}

		create coordinator number: 1;
		ask coordinator {
			do register_all_blocs;
			do start;
		}

	}

}

/**
 * We define only one experiment in the main file : the display of the GIS. 
 * Other displays are defined in the blocs experiments.
 */
experiment display_gis type: gui {
	parameter "Taille de la population :" var: population_size category: 'Model';
	parameter "Nombre de mini-villes :" var: number_of_mini_cities category: 'Model';
	parameter "Nombre d'individus par constellation de mini-villes:" var: city_population category: 'Model';
	output {
		display country_map type: java2D {
			species fronteers aspect: base;
			species mountain aspect: base transparency: 0.15;
			species forest aspect: base transparency: 0.15;
			species water_source aspect: base;
		}

	}

}

experiment main_experiment type: gui {
	parameter "Taille de la population :" var: population_size category: 'Model';
	//	parameter "Nombre de mini-villes :" var: number_of_mini_cities category: 'Model';
	//	parameter "Nombre d'individus par constellation de mini-villes:" var: city_population category: 'Model';	
	output {
	// Monitor des différentes valeurs
		monitor "Agriculture" value: world.tick_resources_used_A["kWh energy"];
		monitor "Urbanisme" value: world.tick_resources_used_U["kWh energy"];
		monitor "Transport" value: world.tick_resources_used_T["kWh energy"];

		// Affichage de la consommation d'énergie
		display "Répartition de la consommation d'énergie pour chaque secteur" type: 2d {
			chart "Consommation d'énergie pour chaque secteur" type: pie {
				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #yellow;
				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
			}

		}

		display "Évolution de la consommation d'énergie pour chaque secteur" type: 2d {
			chart "Évolution de la consommation d'énergie pour chaque secteur" type: series {
				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #yellow;
				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
			}

		}

		// Affichage de la répartition de la surface
		//		display "Répartition de la consommation d'énergie pour chaque secteur" type: 2d {
		//			chart "Consommation d'énergie pour chaque secteur" type: pie {
		//				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #yellow;
		//				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
		//				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
		//			}
		//
		//		}
		//
		//		display "Évolution de la consommation d'énergie pour chaque secteur" type: 2d {
		//			chart "Évolution de la consommation d'énergie pour chaque secteur" type: series {
		//				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #yellow;
		//				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
		//				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
		//			}
		//
		//		}

	}

}

