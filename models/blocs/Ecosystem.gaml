/**
* Name: Ecosystem2
* Bloc représentant l'écosystème qui fournit le bois, le gibier et l'eau aux autres blocs. 
* Author: natmax93
* Tags: 
*/
model Ecosystem2

import "../API/API.gaml"

/**
 * On définit ici les variables globales qui sont liées au bloc écosystème.
 */
global {

/* Setup */
/* Contient les demandes de ressources des autres blocs.
	 * Ce n'est pas vraiment de la production.
	 */
	list<string> production_outputs_ECO <- ["m3_wood", "L water", "kg_meat"];
	list<string> production_inputs_ECO <- [];
	list<string> production_emissions_ECO <- ["gCO2e emissions"]; // émissions absorbées (négatives)

	/* Le stock des différentes ressources naturelles à l'initialisation (cad la France de 2022) */
	float stock_wood <- 3.1; // en milliards
	float stock_meat <- 150.0 * 1; // en millions

	/* Production annuelle de bois */
	float prod_wood <- 0.0878;
	float prod_meat <- 0.9 * 150.0; // Un sanglier européen pèse environ 150 kg

	/* GES absorbé par mois (en moyenne période 2007 à 2020 */
	float GES_absorbe_per_tick <- 83.0; // en milliers

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
species ecosystem parent: bloc {
	string name <- "ecosystem";
	/* Un agent pour la production des ressources */
	eco_producer producer <- nil;

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
	}

	action collect_last_tick_data {
		if (cycle > 0) { // skip it the first tick
			tick_production_ECO <- producer.get_tick_outputs_produced(); // collect production
			tick_absorbed_ECO <- producer.get_tick_emissions(); // collect emissions
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
		map<string, float> tick_emissions <- 0.0;
		float last_wood_variation <- 0.0;
		float last_water_variation <- 0.0;

		/******** INITIALISATION DU PRODUCTEUR ********/
		init {
			tick_production <- ["m3_wood"::0.0, "L water"::0.0, "kg_meat"::0.0];
			tick_emissions["gCO2e emissions"] <- 0.0;
		}

		/******** RESET DES COMPTEURS POUR LE NOUVEAU TICK ********/
		action reset_tick_counters {
			tick_production["m3_wood"] <- 0.0;
			tick_production["L water"] <- 0.0;
			tick_production["kg_meat"] <- 0.0;
			tick_emissions["gCO2e emissions"] <- 0.0;
		}

		/******** PRODUCTION DE RESSOURCES (DEMANDES DES AUTRES SECTEURS) ********/
		bool produce (map<string, float> demand) {
			loop r over: demand.keys {
				float qty <- demand[r];

				/* Production de bois */
				if (r = "m3_wood") {
					if (stock_wood >= qty) {
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
					tick_production[r] <- tick_production[r] + qty;
				}

			}

			/* Émission de GES (absorbtion dans le cas de l'écosystème */
			// Ajout d'une petite variation epsilon arbitraire
			float eps <- 1.0;
			tick_emissions["gCO2e emissions"] <- rnd(GES_absorbe_per_tick - eps, GES_absorbe_per_tick + eps);
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
			chart "Évolution du stock de bois (en milliards)" type: series size: {0.5, 0.5} position: {0, 0} {
				data "Stock de bois" value: stock_wood;
				//				data "Utilisation totale d'eau" value: used_water;
			}

			chart "Évolution du stock du nombre de gibiers (en millions)" type: series size: {0.5, 0.5} position: {0, 0.5} {
				data "Stock de gibier (sangliers)" value: stock_meat / 150.0;
				//				data "Utilisation totale d'eau" value: used_water;
			}

		}

		display Ecosystem_demand_information type: 2d {
			chart "Quantité d'utilisation du bois à chaque tick" type: series size: {0.5, 0.5} position: {0, 0} {
				data "Bois" value: tick_production_ECO["m3_wood"];
			}

			chart "Quantité d'utilisation de viande à chaque tick" type: series size: {0.5, 0.5} position: {0, 0.5} {
				data "Viande" value: tick_production_ECO["kg_meat"];
			}

			chart "Quantité d'utilisation d'eau à chaque tick" type: series size: {0.5, 0.5} position: {0.5, 0} {
				data "Eau" value: tick_production_ECO["L water"];
			}

			chart "Quantité de GES absorbée à chaque tick" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				data "GES" value: tick_absorbed_ECO["gCO2e emissions"];
			}

		}

	}

}