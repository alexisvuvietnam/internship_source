/**
* Name: Environnement
* Bloc représentant l'écosystème qui fournit le bois, le gibier et l'eau aux autres blocs. 
* Écosystème on aurait dû l'appeler environnement en fait...
* Gestion des villes et mini-villes également.
* Author: natmax93
* Tags: 
*/
model Environnement

import "../API/API.gaml"

/**
 * On définit ici les variables globales qui sont liées au bloc écosystème.
 */
global {

/* Contient les demandes de ressources des autres blocs. */
	list<string> production_outputs_ECO <- ["m3_wood", "L water", "kg_meat", "m² land"];
	list<string> production_inputs_ECO <- ["gCO2e emissions"];
	list<string> production_emissions_ECO <- ["gCO2e emissions"]; // émissions absorbées (négatives)

	/* Le stock des différentes ressources naturelles à l'initialisation (cad la France de 2022) */
	float stock_wood <- 3100000000.0; // 3,1 millards de m3 de bois
	float stock_meat <- 150.0 * 1000000.0; // 1 million de sangliers de 150kg
	// Stock d'eau renouvelable : basé sur les précipitations annuelles (~440 milliards m3/an)
	// Convertir en litres et prendre une part utilisable (environ 20% après évapotranspiration)
	float stock_water <- 88e12; // 88 000 milliards de litres (stock annuel renouvelable utilisable)
	float total_surface <- 5.44e11; // Surface de la France métropolitaine en m2
	float forest_surface <- 1.71e11; // La forêt correspond à 171 000 km2 (m2)
	/*  Surface dispo pour les autres secteurs  après avoir retiré la surface de la forêt de base */
	float available_surface <- total_surface - forest_surface;
	float used_surface <- 0.0; // Surface utilisée par les autres secteurs

	/* Production annuelle convertie en production mensuelle*/
	float prod_wood <- 87800000 / 12; //environ 7 millions de m3
	float prod_meat <- 900000 * 150.0 / 12; // Un sanglier européen pèse environ 150 kg
	// Production d'eau par mois (recharge via précipitations et infiltration)
	// Environ 440 milliards m3/an de précipitations, 20% utilisable = 88 milliards m3/an
	float prod_water <- (88e12) / 12; // environ 7 300 milliards de litres par mois

	/* GES absorbé par mois (en moyenne période 2007 à 2020) */
	float GES_absorbe_per_tick <- 8.3e10; // 83 000 tonnes par mois (ici en grammes)

	/* Compteurs pour les données */
	map<string, float> tick_production_ECO <- [];
	map<string, float> tick_absorbed_ECO <- [];

	init { // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0) {
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}

	}

}

/********************************************
 * BLOC PRINCIPAL ECOSYSTEM
 ********************************************/
species environnement parent: bloc {
	string name <- "ecosystem";
	/* Un agent pour la production des ressources */
	eco_producer producer <- nil;
	int population <- 67920000; // Population française
	int city_population <- 0; // Nombre d'habitants par constellation

	/******** INITIALISATION DU BLOC ********/
	action setup {
		list<eco_producer> producers <- [];
		create eco_producer number: 1 returns: producers;
		producer <- first(producers);
	}

	/*
	 * On considère que la population n'a pas d'impact direct sur l'écosystème
	 * (que ça soit pour la production des ressources naturelles et la destruction
	 * ou le développement de l'environnement).
	 * Le paramètre pop est présent uniquement pour respecter la signature
	 * demandée par l'API. À chaque tick l'écosystème se réapprovisonne en
	 * viande, bois et on compte les demandes des autres blocs.
	 */
	action tick (list<human> pop) {
		do natural_regeneration();
		do collect_last_tick_data();
	}

	/* Les ressources naturelles se renouvelle toutes seules  */
	action natural_regeneration {
	/* Mise à jour des stocks */
		stock_wood <- stock_wood + prod_wood;
		stock_meat <- stock_meat + prod_meat;
		stock_water <- stock_water + prod_water; // recharge mensuelle en eau
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_production_ECO <- producer.get_tick_outputs_produced(); // collect production
			tick_absorbed_ECO <- producer.get_tick_emissions(); // collect emissions
			//			write "tick_production_ECO: " + tick_production_ECO;
			//			write "tick_absorded_ECO: " + tick_absorbed_ECO;
			ask eco_producer { // prepare next tick on producer side
				do reset_tick_counters;
			}

		}

	}

	/*
	 * L'écosystème produit du bois, de l'eau et des GES.
	 */
	list<string> get_input_resources_labels {
		return production_inputs_ECO;
	}

	list<string> get_output_resources_labels {
		return production_outputs_ECO;
	}

	species eco_producer parent: production_agent {
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		float last_wood_variation <- 0.0;
		float last_water_variation <- 0.0;

		/******** INITIALISATION DU PRODUCTEUR ********/
		init {
			tick_production <- ["m3_wood"::0.0, "L water"::0.0, "kg_meat"::0.0];
			tick_emissions["gCO2e emissions"] <- 0.0;
		}

		/******** RESET DES COMPTEURS POUR LE NOUVEAU TICK ********/
		action reset_tick_counters {
			tick_production <- ["m3_wood"::0.0, "L water"::0.0, "kg_meat"::0.0, "m² land"::0.0];
			tick_emissions <- ["gCO2e emissions"::0.0];
		}

		/******** PRODUCTION DE RESSOURCES (DEMANDES DES AUTRES SECTEURS) ********/
		bool produce (map<string, float> demand) {
			loop r over: demand.keys {
				float qty <- demand[r];

				/* Production de bois */
				if (r = "m3_wood") {
				// write "Demande de " + qty + " de " + r;
				// write "stock_wood: " + stock_wood;
					if (stock_wood >= qty) {
					// write "Demande de " + qty + " de m3 de bois";
						stock_wood <- stock_wood - qty;
						tick_production[r] <- tick_production[r] + qty;
					} else {
						return false; // stock insuffisant
					}

				}

				/* Production de viande */
				if (r = "kg_meat") {
					if (stock_meat >= qty) {
						stock_meat <- stock_meat - qty;
						tick_production[r] <- tick_production[r] + qty;
					} else {
						return false; // stock insuffisant
					}

				}

				/* Production d’eau */
				if (r = "L water") {
					if (stock_water >= qty) {
						stock_water <- stock_water - qty;
						tick_production[r] <- tick_production[r] + qty;
					} else {
						return false; // stock d'eau insuffisant
					}
				}

				/* Attribution de la surface */
				if (r = "m² land") {
					if (available_surface >= qty) {
						available_surface <- available_surface - qty;
						used_surface <- used_surface + qty;
						tick_production[r] <- tick_production[r] + qty;
					} else {
						return false; // Plus de surface
					}

				}

			}

			/* Émission de GES (absorbtion dans le cas de l'écosystème) */
			// Ajout d'une petite variation epsilon arbitraire
			//float eps <- 1.0;
			tick_emissions["gCO2e emissions"] <- -GES_absorbe_per_tick;
			return true; // production réussie
		}

		/******** MÉTHODES OBLIGATOIRES DE L’API ********/
		map<string, float> get_tick_inputs_used {
			return tick_resources_used; // aucune ressource consommée
		}

		map<string, float> get_tick_outputs_produced {
			return tick_production;
		}

		map<string, float> get_tick_emissions {
			return tick_emissions; // l’écosystème n’émet rien
		}

		action set_supplier (string product, bloc bloc_agent) {
		// Aucun fournisseur externe n’est requis
		}

	}

}

/********************************************
 * EXPERIMENT : VISUALISATION DU BLOC ÉCOSYSTÈME
 ********************************************/
experiment run_ecosystem type: gui {
	output {
		display Ecosystem_stock_information type: 2d {
			chart "Évolution du stock de bois (en m3)" type: series size: {0.5, 0.5} position: {0, 0} {
				data "Stock de bois" value: stock_wood color: #brown;
			}

			chart "Évolution du stock du nombre de gibiers" type: series size: {0.5, 0.5} position: {0, 0.5} {
				data "Stock de gibier (sangliers)" value: stock_meat / 150.0 color: #darkred;
			}

			chart "Évolution du stock d'eau (en milliards L)" type: series size: {0.5, 0.5} position: {0.5, 0} {
				data "Stock d'eau" value: stock_water / 1e9 color: #blue;
			}

			chart "Évolution de la surface dispo (en m2)" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				data "Surface libre" value: available_surface color: #yellow;
			}

		}

		//		display Ecosystem_demand_information type: 2d {
		//			chart "Quantité d'utilisation du bois à chaque tick" type: series size: {0.5, 0.5} position: {0, 0} {
		//				data "Bois" value: tick_production_ECO["m3_wood"] color: #brown;
		//			}
		//
		//			chart "Quantité d'utilisation de viande à chaque tick" type: series size: {0.5, 0.5} position: {0, 0.5} {
		//				data "Viande" value: tick_production_ECO["kg_meat"] color: #darkred;
		//			}
		//
		//			chart "Quantité d'utilisation d'eau à chaque tick" type: series size: {0.5, 0.5} position: {0.5, 0} {
		//				data "Eau" value: tick_production_ECO["L water"] color: #aqua;
		//			}
		//
		//			chart "Quantité de GES absorbée à chaque tick" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
		//				data "GES" value: tick_absorbed_ECO["gCO2e emissions"] color: #black;
		//			}
		//
		//		}
		display Ecosystem_demand_information type: 2d {
			chart "Quantité d'utilisation du bois à chaque tick" type: series size: {0.5, 0.5} position: {0, 0} {
				data "Bois" value: tick_production_ECO["m3_wood"] color: #brown;
			}

			chart "Quantité d'utilisation de viande à chaque tick" type: series size: {0.5, 0.5} position: {0, 0.5} {
				data "Viande" value: tick_production_ECO["kg_meat"] color: #darkred;
			}

			chart "Quantité d'utilisation d'eau à chaque tick" type: series size: {0.5, 0.5} position: {0.5, 0} {
				data "Eau" value: tick_production_ECO["L water"] color: #aqua;
			}

			chart "Quantité de GES absorbée à chaque tick" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				data "GES" value: tick_absorbed_ECO["gCO2e emissions"] color: #black;
			}

		}

		monitor "Bois" value: tick_production_ECO["m3_wood"];
		monitor "Viande" value: tick_production_ECO["kg_meat"];
		monitor "Eau" value: tick_production_ECO["L water"];
		monitor "GES" value: tick_absorbed_ECO["gCO2e emissions"];
		display Surface_usage type: 2d {
			chart "Utilisation de la surface pour chaque secteur (en km2)" type: pie {
				data "Forêt" value: forest_surface / 1e6 color: #green;
				data "Dispo" value: available_surface / 1e6 color: #blue;
				data "Autre" value: used_surface / 1E6 color: #gray;
			}

		}

	}

}