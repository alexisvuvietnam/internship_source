model Ecosystem

import "../API/API.gaml"


/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global {

	/* Setup */
    list<string> production_outputs_ECO <- ["m3_wood", "L_water"];
    list<string> production_inputs_ECO <- [];
    list<string> production_emissions_ECO <- ["gCO2e emissions"]; // émissions absorbées (négatives)
	
	/* Production data */
    map<string, float> tick_production_ECO <- [];
    map<string, float> tick_absorbed_ECO <- [];
    map<string, float> tick_stock_variation_ECO <- [];

    /* Stocks globaux de l'écosystème */
    float stock_wood <- 5000000.0; 
    float stock_water <- 200000000.0; 
    float stock_GES <- 0.0;

    /* Taux de régénération naturels */
    float regen_forest_rate <- 0.02;  
    float regen_water_rate <- 0.05;   

    /* Taux d'absorption des GES */
    float absorption_rate <- 0.3;     
    	
	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
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

    eco_producer producer <- nil;
    eco_absorber absorber <- nil;


    /******** INITIALISATION DU BLOC ********/
    action setup {
		list<eco_producer> producers <- [];
		list<eco_absorber> absorbers <- [];
		create eco_producer number:1 returns:producers;
		create eco_absorber number:1 returns:absorbers;
		producer <- first(producers);
		absorber <- first(absorbers);
	}


    /******** EXÉCUTION D'UN TICK ********/
    action tick(list<human> pop) {

        /* Régénération des ressources naturelles */
        ask producer {
            do natural_regeneration;
        }
        
        /* Note: L'absorption des GES sera gérée par le coordinateur qui collecte */
        /* les émissions de tous les blocs et appelle absorb_emissions() */

        /* Mise à jour des données pour l'expérience */
        do collect_last_tick_data();
    }


    /******** RÉCUPÉRATION DES DONNÉES POUR LES CHARTS ********/
    action collect_last_tick_data {

        /* Production bois/eau ce tick */
        tick_production_ECO <- producer.get_tick_outputs_produced();

        /* Quantité de GES absorbée ce tick */
        tick_absorbed_ECO <- ["gCO2e emissions":: absorber.last_absorbed];

        /* Variations de stock (bois, eau, GES) */
        tick_stock_variation_ECO <- [
            "wood" :: producer.last_wood_variation,
            "water" :: producer.last_water_variation,
            "GES" :: absorber.last_GES_variation
        ];

        /* Réinitialisation des compteurs internes */
        ask producer { do reset_tick_counters; }
        ask absorber { do reset_tick_counters; }
    }

    /******** MÉTHODES REQUISES PAR L'API ********/
    list<string> get_output_resources_labels {
        return production_outputs_ECO;
    }

    list<string> get_input_resources_labels {
        return production_inputs_ECO;
    }
    
    list<string> get_emissions_labels {
        return production_emissions_ECO;
    }
    
    production_agent get_producer {
        return producer;
    }
    
    action set_external_producer(string product, bloc bloc_agent) {
        // L'écosystème n'a pas de fournisseurs externes
    }
    
    action population_activity(list<human> pop) {
        // L'écosystème n'a pas de consommation directe par la population
        // La demande en ressources (bois, eau) se fait via les autres blocs
    }
    
    /******** ABSORPTION DES ÉMISSIONS GLOBALES ********/
    action absorb_emissions(float total_emissions) {
        ask absorber {
            do absorb(total_emissions);
        }
    }

}


/********************************************
 * PRODUCTEUR : GÉNÈRE BOIS & EAU
 ********************************************/
species eco_producer parent: production_agent {

    map<string, float> tick_production <- [];
    map<string, float> tick_inputs_used <- [];
    map<string, float> tick_emissions <- [];

    float last_wood_variation <- 0.0;
    float last_water_variation <- 0.0;


    /******** INITIALISATION DU PRODUCTEUR ********/
    init {
        tick_production <- ["m3_wood"::0.0, "L_water"::0.0];
        tick_inputs_used <- [];
        tick_emissions <- [];
    }


    /******** PROCESSUS DE RÉGÉNÉRATION NATUREL ********/
    action natural_regeneration {

        /* Croissance naturelle */
        float reg_w <- stock_wood * regen_forest_rate;
        float reg_wat <- stock_water * regen_water_rate;

        /* Mise à jour des stocks */
        stock_wood <- stock_wood + reg_w;
        stock_water <- stock_water + reg_wat;

        /* Enregistrement des variations */
        last_wood_variation <- reg_w;
        last_water_variation <- reg_wat;
    }


    /******** RESET DES COMPTEURS POUR LE NOUVEAU TICK ********/
    action reset_tick_counters {
        tick_production["m3_wood"] <- 0.0;
        tick_production["L_water"] <- 0.0;

        last_wood_variation <- 0.0;
        last_water_variation <- 0.0;
    }


    /******** PRODUCTION DE RESSOURCES (API) ********/
    bool produce(map<string,float> demand) {

        loop r over: demand.keys {

            float qty <- demand[r];

            /* Production de bois */
            if (r = "m3_wood") {
                if (stock_wood >= qty) {
                    stock_wood <- stock_wood - qty;
                    tick_production[r] <- tick_production[r] + qty;
                    last_wood_variation <- -qty;
                } else {
                    return false; // stock insuffisant
                }
            }

            /* Production d’eau */
            if (r = "L_water") {
                if (stock_water >= qty) {
                    stock_water <- stock_water - qty;
                    tick_production[r] <- tick_production[r] + qty;
                    last_water_variation <- -qty;
                } else {
                    return false;
                }
            }
        }
        return true;  // production réussie
    }


    /******** MÉTHODES OBLIGATOIRES DE L’API ********/
    map<string, float> get_tick_inputs_used {
        return tick_inputs_used; // aucune ressource consommée
    }

    map<string, float> get_tick_outputs_produced {
        return tick_production;
    }

    map<string, float> get_tick_emissions {
        return tick_emissions; // l’écosystème n’émet rien
    }

    action set_supplier(string product, bloc bloc_agent) {
        // Aucun fournisseur externe n’est requis
    }

}


/********************************************
 * ABSORBEUR DE GES
 ********************************************/
species eco_absorber {

    float last_absorbed <- 0.0;
    float last_GES_variation <- 0.0;


    /******** ABSORPTION DES GAZ À EFFET DE SERRE ********/
    action absorb(float emissions) {

        float absorbed <- emissions * absorption_rate;

        /* Quantité absorbée */
        last_absorbed <- absorbed;

        /* Variation du stock de GES (négative si absorption) */
        last_GES_variation <- -absorbed;

        /* Mise à jour du stock global */
        stock_GES <- stock_GES + emissions - absorbed;
    }


    /******** RESET DES VALEURS POUR LE PROCHAIN TICK ********/
    action reset_tick_counters {
        last_absorbed <- 0.0;
        last_GES_variation <- 0.0;
    }
}



/********************************************
 * EXPERIMENT : VISUALISATION DU BLOC ÉCOSYSTÈME
 ********************************************/
experiment run_ecosystem type: gui {

    output {

        display "Ecosystem Indicators" {

            /* -----------------------------
               1. ÉVOLUTION DES STOCKS
               ----------------------------- */
            chart "Stocks evolution" type: series size:{0.5,0.33} position:{0,0} {
                data "Stock bois" value: stock_wood;
                data "Stock eau" value: stock_water;
                data "Stock GES" value: stock_GES;
            }

            /* -----------------------------
               2. PRODUCTION PAR TICK
               ----------------------------- */
            chart "Production ce tick" type: series size:{0.5,0.33} position:{0.5,0} {
                loop r over: production_outputs_ECO {
                    data r value: tick_production_ECO[r];
                }
            }

            /* -----------------------------
               3. ABSORPTION DES GES
               ----------------------------- */
            chart "Absorption GES" type: series size:{0.5,0.33} position:{0,0.33} {
                data "GES absorbés" value: tick_absorbed_ECO["gCO2e emissions"];
            }

            /* -----------------------------
               4. VARIATIONS DES STOCKS
               ----------------------------- */
            chart "Variations des stocks" type: series size:{0.5,0.33} position:{0.5,0.33} {
                data "Δ bois" value: tick_stock_variation_ECO["wood"];
                data "Δ eau" value: tick_stock_variation_ECO["water"];
                data "Δ GES" value: tick_stock_variation_ECO["GES"];
            }
        }
    }
}