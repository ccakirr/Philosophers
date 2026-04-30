/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   main.c                                             :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ccakir <ccakir@student.42.fr>              +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/04/29 22:01:48 by ccakir            #+#    #+#             */
/*   Updated: 2026/04/30 14:45:26 by ccakir           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "./philosophers.h"

void	cleanup(t_table *table)
{
	int	i;

	i = -1;
	while (++i < table->philo_count)
		pthread_mutex_destroy(&table->forks[i]);
	i = -1;
	while (++i < table->philo_count)
		pthread_mutex_destroy(&table->philos[i].philo_mutex);
	pthread_mutex_destroy(&table->print_mutex);
	pthread_mutex_destroy(&table->dead_mutex);
	free(table->philos);
	free(table->forks);
	if (table->threads)
		free(table->threads);
}

int	main(int ac, char **av)
{
	t_table	table;

	table.threads = NULL;
	if (ac != 5 && ac != 6)
		exit(1);
	if (!check_args(av))
	{
		table.philo_count = ft_atoi(av[1]);
		table.time_to_die = ft_atoi(av[2]);
		table.time_to_eat = ft_atoi(av[3]);
		table.time_to_sleep = ft_atoi(av[4]);
		if (ac == 6)
			table.must_eat = ft_atoi(av[5]);
		else
			table.must_eat = -1;
	}
	else
	{
		printf("Parsing error!\n");
		return (1);
	}
	init_table(&table);
	start_simulation(&table);
	cleanup(&table);
	return (0);
}
