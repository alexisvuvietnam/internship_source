# Several points of view

About the use of Machine Learning model for the dataset lerning: The comparation between Logistic Regression and other algorithms of Tree Learning is quite problematic:

1. The way each algorithm "learns" the model: Whereas the family off linear regression choose to learn a feature-related dataset by applying weights on each feature of the data, the tree algorithm choose to create a rule based on the correspondence/relevance/entropy between the feature and the output. Consequently, tree learning levels each feature according to its importance by create the dependence between them, whereas linear learning makes every feature independent (and additive).

2. The way of preprocessing the dataset: Tree learning does not require (or it requires in the most minimalistic way) the preprocessing of data, while linear learning requires to scale several features on a general standard, and even encode a feature into several different others. Therefore, in fact, the different methods of explanation can be a bit separated.

To do this experiment, there are two factors to be sacrificed, so that the comparation can occur in the most objective way:
1. The sacrifice of accuracy: To assure that all models have the same input features, the one-hot encoding cannot be applied to the linear learning, which is able to diversify a categorical feature.

2. The sacrifice of 

## Over global explanation

1. 