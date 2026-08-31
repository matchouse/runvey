package config

type Mode string

const (
	EnvDevelopment Mode = "development"
	EnvStaging     Mode = "staging"
	EnvProduction  Mode = "production"
)

func (m Mode) IsValid() bool {
	switch m {
	case EnvDevelopment, EnvProduction, EnvStaging:
		return true
	default:
		return false
	}
}

func (m Mode) IsDevelopment() bool {
	return m == EnvDevelopment
}

func (m Mode) IsProduction() bool {
	return m == EnvProduction
}
